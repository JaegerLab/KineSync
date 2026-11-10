function p = seg_likelihood(seg)
    %SEG_LIKELIHOOD  Per-frame likelihood rebuilt from segment flags.
    %
    %   p = Pose.seg_likelihood(seg)   returns an nFrames x 1 vector.
    %
    %   Used when a fixed trace is saved as a new body part, so that its
    %   _likelihood column says how much each frame can be trusted.
    
    % ---- values per flag (tune here) -----------------------------------------
    P_USER_GOOD = 1;      % flag  2, shorter than seedWidth (confirmed by the user)
    P_SEED      = 0.95;   % flag  2, seed made by the algorithm
    P_GOOD      = 0.9;    % flag  1, presumed good (propagation)
    P_UNSURE    = 0.5;    % flag -2 questionable, flag 0 unflagged
    P_BAD       = 0.1;    % flag -1, presumed bad (propagation)
    P_USER_BAD  = 0;      % flag -3, rejected by the user
    
    f = seg.flag(:);
    isSeed   = f == 2;
    userGood = isSeed & ~(seg.len(:) >= seg.seedWidth);   % NaN seedWidth: all user
    
    pk = P_UNSURE * ones(size(f));
    pk(isSeed)   = P_SEED;
    pk(userGood) = P_USER_GOOD;
    pk(f == 1)   = P_GOOD;
    pk(f == -1)  = P_BAD;
    pk(f == -3)  = P_USER_BAD;
    
    p = repelem(pk, seg.len(:));
end
