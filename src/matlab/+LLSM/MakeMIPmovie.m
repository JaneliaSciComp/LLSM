function MakeMIPmovie(root,subPath)
    % root = 'D:\Images\LLSM\Pfisterer';
    % subPath = '20171108_Pfisterer\TimeLapse3\CPPdecon\MIPs';
    outName = subPath;
    klbEnd = strfind(subPath,'KLB');
    if (~isempty(klbEnd))
        outName = outName(1:klbEnd-1);
    end
    mipEnd = strfind(subPath,'\MIPs');
    if (~isempty(mipEnd))
        outName = outName(1:mipEnd-1);
    end
    seps = regexpi(outName,'[/\\]');
    outName(seps) = '_';
    moviePathName = fullfile(root,[outName,'.mp4']);
    if (exist(moviePathName,'file'))
        return
    end

    colors = single([0,1,0;1,0,1;1,1,0;0,1,1]);

    extension = 'tif';
    
    imageList = dir(fullfile(root,subPath,['*.',extension]));
    if (isempty(imageList))
        imageList = dir(fullfile(root,subPath,'*.klb'));
        if (isempty(imageList))
%             warning('No files found in %s',fullfile(root,subPath));
            return
        end
        extension = 'klb';
    end
    try
        [~,chans,~,stacks,iter] = LLSM.ParseFileNames(imageList,extension);
    catch err
%         warning('Could not parse names from %s',fullfile(root,subPath));
        imD = MicroscopeData.ReadMetadata(fullfile(root,subPath),false);
        if (isempty(imD))
            return
        end
        extension = 'json';
    end
    
    if (~strcmp(extension,'json'))
        if (isempty(iter))
            numFrames = max(stacks(:))+1;
        else
            numFrames = max(iter(:))+1;
        end
        numChans = max(chans(:))+1;
    else
        numFrames = imD.NumberOfFrames;
        numChans = imD.NumberOfChannels;
        stacks = [];
        chans = [];
        iter = [];
    end
    
    if (numFrames < 20)
        return
    end

    colorMultiplier = zeros(1,1,3,length(numChans),'single');
    for c=1:numChans
        colorMultiplier(1,1,:,c) = colors(c,:);
    end

    frameDir = fullfile(root,subPath,outName);
    if (exist(frameDir,'dir'))
        rmdir(frameDir,'s');
    end
    mkdir(frameDir);

    prgs = Utils.CmdlnProgress(numFrames,true,outName);
    for t=1:numFrames   
        if (isempty(iter))
            timeMask = stacks==t-1;
        else
            timeMask = iter==t-1;
        end
        chanMask = chans==0;
        i = timeMask & chanMask;
        try
            if (strcmp(extension,'json'))
                imIntensity = squeeze(MicroscopeData.Reader(imD.imageDir,'timeRange',[t,t],'getMIP',true));
            else
                if (strcmp(extension,'tif'))
                    im = imread(fullfile(root,subPath,imageList(i).name));
                elseif (strcmp(extension,'klb'))
                    im = max(MicroscopeData.KLB.readKLBstack(['"',fullfile(root,subPath,imageList(i).name),'"']),[],3);
                end
                imIntensity = zeros(size(im,1),size(im,2),numChans,'single');
                for c=1:numChans
                    chanMask = chans==c-1;
                    i = timeMask & chanMask;
                    if (strcmp(extension,'tif'))
                        imIntensity(:,:,c) = imread(fullfile(root,subPath,imageList(i).name));
                    elseif (strcmp(extension,'klb'))
                        imIntensity(:,:,c) = max(['"',MicroscopeData.KLB.readKLBstack(fullfile(root,subPath,imageList(i).name)),'"'],[],3);
                    end
                end
            end
            
            imColors = zeros(size(imIntensity,1),size(imIntensity,2),3,numChans,'single');
            imIntensity = double(imIntensity);
            for c=1:numChans
                im = imIntensity(:,:,c);
                im = mat2gray(im);
                im = ImUtils.BrightenImages(im);
                im = mat2gray(im);
                imIntensity(:,:,c) = im;
                color = repmat(colorMultiplier(1,1,:,c),size(im,1),size(im,2),1);
                imColors(:,:,:,c) = repmat(im,1,1,3).*color;
            end
            
            imMax = max(imIntensity,[],3);
            imIntSum = sum(imIntensity,3);
            imIntSum(imIntSum==0) = 1;
            imColrSum = sum(imColors,4);
            imFinal = imColrSum.*repmat(imMax./imIntSum,1,1,3);
            imFinal = im2uint8(imFinal);
            
            sizeEven = size(imFinal)/2;
            sizeEven = sizeEven([1,2]);
            sizeEven = sizeEven~=round(sizeEven);
            imFinal(end:end+sizeEven(1),end:end+sizeEven(2),:) = 0;
            
            sz = size(imFinal);
            if (sz(1)>sz(2))
                imFinal = imrotate(imFinal,90);
            end

            imwrite(imFinal,fullfile(frameDir,sprintf('%04d.tif',t)));
        catch err
            warning(err.message);
            prgs.ClearProgress(false);
            return
            prgs.StopUsingBackspaces();
        end
        prgs.PrintProgress(t);
    end

    fps = min(60,numFrames/10);
    fps = max(fps,7);
    fps = round(fps);
    
    MovieUtils.MakeMP4_ffmpeg(1,numFrames,frameDir,fps);
    copyfile(fullfile(frameDir,[outName,'.mp4']),fullfile(root,'.'));
    rmdir(frameDir,'s');

    prgs.ClearProgress(true);
end