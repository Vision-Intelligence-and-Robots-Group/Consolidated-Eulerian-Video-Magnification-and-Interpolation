
%% Input the data mat vidFile,return the magnification data in a Mat
%

function Video =  Mat_amplify_video(vidFile, resultsDir,alpha, lambda_c, r1, r2, chromAttenuation,pNum)

   % Read video
    [~,vidName] = fileparts(vidFile);   %vidName:face
     outName = fullfile(resultsDir,[vidName 'MER_result-iir-r1-' num2str(r1)...
         '-r2-' num2str(r2)...
         '-alpha-' num2str(alpha) ...
         '-lambda_c-' num2str(lambda_c) ...
         '-chromAtn-' num2str(chromAttenuation) '.avi']);

    % Read video
    vid = VideoReader(vidFile);
    % Extract video info
    vidHeight = vid.Height;
    vidWidth = vid.Width;  
    nChannels = 3;
    fr = vid.FrameRate;
    len = vid.NumberOfFrames; 
    nF = len
    temp = struct('cdata', ...
		  zeros(vidHeight, vidWidth, nChannels, 'uint8'), ...
		  'colormap', []); 

    startIndex = 1;
    endIndex = len;

    vidOut = VideoWriter(outName);
    vidOut.FrameRate = fr;

    open(vidOut)

    % get the data for the first frame of the video
    temp.cdata = read(vid, startIndex);
    [img1,~] = frame2im(temp);  

    rgbframe = im2double(img1);     % type:uint 8 --> double
    frame = rgb2ntsc(rgbframe);     % transfer rgbframe to NTSC color space (luminance (Y) and chroma (I and Q) color components)

    % get the 3-channel Laplace pyramid of the first frame
    % The second through the eighth layers of the Laplace pyramid are Gaussian pyramids subtracting the upsampled image from the same layer, but the first layer of the Laplace pyramid is Gaussian pyramid, and the first layer does not subsample, and no subtraction is performed.
    % pyr: The column vector that stores the values of the Laplace pyramid
    % The first element of pyr is the first element of the last layer of pyramid, 
    % the last element of pyris the last element of the top layer of pyramid.
    % pid: The dimensions of the layers of Laplace pyramid (8 layers)
    [pyr,pind] = buildLpyr(frame(:,:,1),'auto');       
    pyr = repmat(pyr,[1 3]);
    [pyr(:,2),~] = buildLpyr(frame(:,:,2),'auto');
    [pyr(:,3),~] = buildLpyr(frame(:,:,3),'auto');  % pyr: Laplacian Pyramid for 3 channels
    
    % arrange for output
    im = imresize(img1, [NaN 140]); % fix the width of output frame to 140
    [rs ,cs ,~] =size(im);
    pmag_data = zeros([rs ,cs, pNum], 'uint8');
    pmag_data(:,:,1) = rgb2gray(im);    % output video: rgb --> gray 
    
    writeVideo(vidOut,pmag_data(:,:,1));

    Lap_pyr = zeros([size(pyr),nF],'double');   % pyr for every frame
    Lap_pyr(:,:,1)= pyr;
    for i=startIndex+1:endIndex
        % repeat the operations for first frame: read data -> transfer rgb to ntsc space
        temp.cdata = read(vid, i);
        [img,~] = frame2im(temp);

        rgbframe = im2double(img);
        frame = rgb2ntsc(rgbframe);
        
        % 3 channel Laplace Pyramid 
        [pyr(:,1),~] = buildLpyr(frame(:,:,1),'auto');
        [pyr(:,2),~] = buildLpyr(frame(:,:,2),'auto');
        [pyr(:,3),~] = buildLpyr(frame(:,:,3),'auto');

        Lap_pyr(:,:,i)= pyr;
    end
    
  
    conv_mat = conv_matrix(nF,r1,r2);   % the triangular matrix for magnification
    

    pos = 0:1/(pNum-1):1;
    
    for frame_no = 2 : numel(pos)-1
        loc = nF*pos(frame_no);
        prev = floor(loc);  % index of prev frame
        alph = loc - prev;
        if(prev < 1)
            prev = 1;
            alph = 0;
        end
        
        rgbPyr1 = zeros(size(pyr), 'double');
        rgbPyr2 = zeros(size(pyr), 'double');
% %         Need to be improved
% %         for index = 1:prev
% %             rgbPyr1 = rgbPyr1 + conv_mat(prev,index)*Lap_pyr(:,:,index);
% %             rgbPyr2 = rgbPyr2 + conv_mat(prev+1,index)*Lap_pyr(:,:,index);
% %         end
% %         rgbPyr2 = rgbPyr2 + conv_mat(prev+1,prev+1)*Lap_pyr(:,:,prev+1);
        a = repmat(conv_mat(prev, 1:prev), [3, 1]);
        a = a( : )';    
        b = repmat(conv_mat(prev+1, 1:prev+1), [3, 1]); 
        b = b( : )';   
        
        c = repmat(a, size(Lap_pyr, 1),1);  
        c = reshape(c, [size(Lap_pyr, 1),3, prev]);
        d = repmat(b, size(Lap_pyr, 1),1);
        d = reshape(d, [size(Lap_pyr, 1),3, prev+1]);

        rgbPyr1 = sum(c .* Lap_pyr(:,:, 1:prev), 3);    
        rgbPyr2 = sum(d .* Lap_pyr(:,:, 1:prev+1), 3);

%         rgbPyr1 = sum(repmat(conv_mat(prev, 1:prev), [size(Lap_pyr, 1) size(Lap_pyr, 2) 1]) .* Lap_pyr(:,:, 1:prev), 3);
%         rgbPyr2 = sum(repmat(conv_mat(prev+1, 1:prev+1), [size(Lap_pyr, 1) size(Lap_pyr, 2) 1]) .* Lap_pyr(:,:, 1:prev+1), 3);

        
        temp.cdata = read(vid, prev);
        [prev_img,~] = frame2im(temp);
        temp.cdata = read(vid, prev+1);
        [next_img,~] = frame2im(temp);
        % get the amplified frame of the frame_prev and frame_next(prev+1)
        prev_img = pyr_amplify(prev_img,rgbPyr1,pind,alpha,lambda_c,chromAttenuation);
        next_img = pyr_amplify(next_img,rgbPyr2,pind,alpha,lambda_c,chromAttenuation);
              
        img = (1 - alph)*prev_img + alph*next_img;
        pmag_data(:,:,frame_no)= rgb2gray(imresize(img, [NaN 140]));
        % Writes a frame to a video. The first parameter is the video object, and the second parameter is the frames of the video
        writeVideo(vidOut,pmag_data(:,:,frame_no));
    end
    
    rgbPyr = zeros(size(pyr), 'double');   
    for index = 1:nF
        rgbPyr = rgbPyr + conv_mat(nF,index)*Lap_pyr(:,:,index);
    end
    
    temp.cdata = read(vid, nF);
    [video_nF,~] = frame2im(temp);
    img = pyr_amplify(video_nF,rgbPyr,pind,alpha,lambda_c,chromAttenuation);
    pmag_data(:,:,pNum)= rgb2gray(imresize((img), [NaN 140]));% Maybe not precise
    writeVideo(vidOut,pmag_data(:,:,pNum));
    Video = pmag_data;

end
function out = pyr_amplify(img,filtered,pind,alpha,lambda_c,chromAttenuation)

        %% amplify each spatial frequency bands according to Figure 6 of our paper
        [vidHeight ,vidWidth ,~] = size(img);

        rgbframe = im2double(img);
        frame = rgb2ntsc(rgbframe);
        
        ind = size(filtered,1);
        nLevels = size(pind,1);
        
        delta = lambda_c/8/(1+alpha);
        
        % the factor to boost alpha above the bound we have in the
        % paper. (for better visualization)
        exaggeration_factor = 2;
        
        % compute the representative wavelength lambda for the lowest spatial
        % freqency band of Laplacian pyramid
        
        lambda = (vidHeight^2 + vidWidth^2).^0.5/3; % 3 is experimental constant
        
        for l = nLevels:-1:1
            indices = ind-prod(pind(l,:))+1:ind;
            % compute modified alpha for this level
            currAlpha = lambda/delta/8 - 1;
            currAlpha = currAlpha*exaggeration_factor;
            
            if (l == nLevels || l == 1) % ignore the highest and lowest frequency band
                filtered(indices,:) = 0;
            elseif (currAlpha > alpha)  % representative lambda exceeds lambda_c
                filtered(indices,:) = alpha*filtered(indices,:);
            else
                filtered(indices,:) = currAlpha*filtered(indices,:);
            end
            
            ind = ind - prod(pind(l,:));
            % go one level down on pyramid, 
            % representative lambda will reduce by factor of 2
            lambda = lambda/2;
        end
        
        
        %% Render on the input video
        output = zeros(vidHeight,vidWidth,3);
        
        output(:,:,1) = reconLpyr(filtered(:,1),pind);
        output(:,:,2) = reconLpyr(filtered(:,2),pind);
        output(:,:,3) = reconLpyr(filtered(:,3),pind);
        % Suppressing the color channel, relatively amplifies the brightness channel
        output(:,:,2) = output(:,:,2)*chromAttenuation;
        output(:,:,3) = output(:,:,3)*chromAttenuation;
        % add the amplified vedio to the original one
        output = frame + output;
        % transfer type ntsc to rgb
        output = ntsc2rgb(output);
        % Correction for the values beyond normalization
        output(output > 1) = 1;
        output(output < 0) = 0;
        out = im2uint8(output);    

end
