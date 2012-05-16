classdef FeedbackSystem < RobotLibSystem
  
  properties
    sys1
    sys2
    sys1ind=[]
    sys2ind=[]
  end
  
  methods
    function obj = FeedbackSystem(sys1,sys2)
      obj = obj@RobotLibSystem(sys1.getNumContStates()+sys2.getNumContStates(),...
        sys1.getNumDiscStates()+sys2.getNumDiscStates(),...
        sys1.getNumInputs(), sys1.getNumOutputs(), false, sys1.isTI() & sys2.isTI());
      typecheck(sys1,'RobotLibSystem');
      typecheck(sys2,'RobotLibSystem');
      
      [sys1,sys2] = matchCoordinateFramesForCombination(sys1,sys2,false);
      [sys2,sys1] = matchCoordinateFramesForCombination(sys2,sys1,true);

      if (sys1.isDirectFeedthrough() && sys2.isDirectFeedthrough())
        error('RobotLib:FeedbackSystem:AlgebraicLoop','algebraic loop');
      end
      
      ind=0;
      n=sys1.getNumDiscStates();
      obj.sys1ind = ind+(1:n)';
      ind=ind+n;
      n=sys2.getNumDiscStates();
      obj.sys2ind=  ind+(1:n)'; ind=ind+n;

      n=sys1.getNumContStates();
      obj.sys1ind = [obj.sys1ind; ind+(1:n)'];  ind=ind+n;
      n=sys2.getNumContStates();
      obj.sys2ind = [obj.sys2ind; ind+(1:n)'];  
      
      obj = setNumZeroCrossings(obj,sys1.getNumZeroCrossings()+sys2.getNumZeroCrossings()+sum(~isinf([sys1.umin;sys1.umax;sys2.umin;sys2.umax])));
      obj = setNumStateConstraints(obj,sys1.getNumStateConstraints()+sys2.getNumStateConstraints());
      obj = setSampleTime(obj,[sys1.getSampleTime(),sys2.getSampleTime()]);

      obj = setInputFrame(obj,sys1.getInputFrame());
      obj = setOutputFrame(obj,sys1.getOutputFrame());
      
      obj.sys1=sys1;
      obj.sys2=sys2;
    end
    
    
    function xdn = update(obj,t,x,u)
      [x1,x2]=decodeX(obj,x);
      [y1,y2]=getOutputs(obj,t,x,u);
      xdn=[];
      if (obj.sys1.getNumDiscStates()) xdn=[xdn;update(obj.sys1,t,x1,sat1(obj,y2+u))]; end
      if (obj.sys2.getNumDiscStates()) xdn=[xdn;update(obj.sys2,t,x2,sat2(obj,y1))]; end
    end
    function xcdot = dynamics(obj,t,x,u)
      [x1,x2]=decodeX(obj,x);
      [y1,y2]=getOutputs(obj,t,x,u);
      xcdot=[];
      if (obj.sys1.getNumContStates()) xcdot=[xcdot;dynamics(obj.sys1,t,x1,sat1(obj,y2+u))]; end
      if (obj.sys2.getNumContStates()) xcdot=[xcdot;dynamics(obj.sys2,t,x2,sat2(obj,y1))]; end
    end
    function y = output(obj,t,x,u)
      [y1,y2] = getOutputs(obj,t,x,u);
      y=y1;
    end
    
    function x0=getInitialState(obj)
      x0=encodeX(obj,getInitialState(obj.sys1),getInitialState(obj.sys2));
    end
    
    function x0=getInitialStateWInput(obj,t,x,u)
      [x1,x2]=decodeX(obj,x);
      [y1,y2]=getOutputs(obj,t,x,u);
      x1=getInitialStateWInput(obj.sys1,t,x1,sat1(obj,y2+u));
      x2=getInitialStateWInput(obj.sys2,t,x2,sat2(obj,y1));
      x0=encodeX(obj,x1,x2);
      % note: this is not perfect (y2 could change after updating x1).  how
      % does simulink do it on the backend? 
    end
    
    function zcs = zeroCrossings(obj,t,x,u)
      [x1,x2]=decodeX(obj,x);
      [y1,y2]=getOutputs(obj,t,x,u);
      if (getNumZeroCrossings(obj.sys1)>0)
        zcs=zeroCrossings(obj.sys1,t,x1,sat1(obj,y2+u));
      else
        zcs=[];
      end
      if (getNumZeroCrossings(obj.sys2)>0)
        zcs=[zcs;zeroCrossings(obj.sys2,t,x2,sat2(obj,y1))];
      end
      
      % sys1 umin
      ind=find(~isinf(obj.sys1.umin));
      if (~isempty(ind)) zcs=[zcs;y2(ind)+u(ind) - obj.sys1.umin(ind)]; end
      
      % sys1 umax
      ind=find(~isinf(obj.sys1.umax));
      if (~isempty(ind)) zcs=[zcs;obj.sys1.umax(ind) - y2(ind)-u(ind)]; end
        
      % sys2 umin
      ind=find(~isinf(obj.sys2.umin));
      if (~isempty(ind)) zcs=[zcs;y1(ind) - obj.sys2.umin(ind)]; end
      
      % sys2 umax
      ind=find(~isinf(obj.sys2.umax));
      if (~isempty(ind)) zcs=[zcs;obj.sys2.umax(ind) - y1(ind)]; end
    end
    
    function con = stateConstraints(obj,x)
      [x1,x2]=decodeX(obj,x);
      if (getNumStateConstraints(obj.sys1)>0)
        con=stateConstraints(obj.sys1,x1);
      else
        con=[];
      end
      if (getNumStateConstraints(obj.sys2)>0)
        con=[con;stateConstraints(obj.sys2,x2)];
      end
    end
  end
  
  methods (Access=private)
    function [x1,x2] = decodeX(obj,x)
      x1=x(obj.sys1ind);
      x2=x(obj.sys2ind);
    end
    function x = encodeX(obj,x1,x2)
      x(obj.sys2ind)=x2;  % x2 first so it only allocates once
      x(obj.sys1ind)=x1;
    end
    function u1=sat1(obj,u1)
      u1=min(max(u1,obj.sys1.umin),obj.sys1.umax);
    end
    function u2=sat2(obj,u2)
      u2=min(max(u2,obj.sys2.umin),obj.sys2.umax);
    end
    function [y1,y2] = getOutputs(obj,t,x,u)
      [x1,x2]=decodeX(obj,x);
      if (~obj.sys1.isDirectFeedthrough()) % do sys1 first
        y1=output(obj.sys1,t,x1);  % doesn't need u
        y2=output(obj.sys2,t,x2,sat2(obj,y1));
      else % do sys2 first
        y2=output(obj.sys2,t,x2);  % doesn't need u
        y1=output(obj.sys1,t,x1,sat1(obj,y2+u));
      end
    end
  end
  
end
    
