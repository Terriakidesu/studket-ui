import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/profile_picture_api.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.accountId,
    required this.radius,
    this.backgroundColor,
    this.label,
  });

  final int? accountId;
  final double radius;
  final Color? backgroundColor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: ProfilePictureApi.resolveForAccount(accountId),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String? imageUrl = snapshot.data;
        final String fallbackLabel = (label ?? '?').trim().isEmpty
            ? '?'
            : (label ?? '?').trim().characters.first.toUpperCase();
        final bool isSvg = (imageUrl ?? '').toLowerCase().endsWith('.svg');
        final double diameter = radius * 2;
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: imageUrl != null && !isSvg
              ? CachedNetworkImageProvider(imageUrl)
              : null,
          child: imageUrl == null
              ? Text(fallbackLabel)
              : isSvg
              ? SizedBox(
                  width: diameter,
                  height: diameter,
                  child: ClipOval(
                    child: ColoredBox(
                      color: backgroundColor ?? Colors.transparent,
                      child: Center(
                        child: SvgPicture.network(
                          imageUrl,
                          width: diameter,
                          height: diameter,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}
