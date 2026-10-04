import { Module } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { IntakeModule } from './intake/intake.module';
import { PrismaModule } from './prisma/prisma.module';
import { ConflictModule } from './conflict/conflict.module';
import { SupabaseModule } from './supabase/supabase.module';
import { ChatbotModule } from './chatbot/chatbot.module';
import { LabelRecognitionModule } from './label-recognition/label-recognition.module';
import { SupplementSearchService } from './supplement-search.service';
import { PrismaService } from './prisma/prisma.service';
import { RecommendModule } from './recommend/recommend.module';
import { CabinetModule } from './cabinet/cabinet.module';
import { RemindersModule } from './reminders/reminders.module';
import { ReviewModule } from './review/review.module';
import { AdminModule } from './admin/admin.module';
import { PrismaExceptionFilter } from './common/prisma-exception.filter';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    SupabaseModule,
    AuthModule,
    IntakeModule,
    ConflictModule,
    RecommendModule,
    ChatbotModule,
    LabelRecognitionModule,
    RemindersModule,
    CabinetModule,
    ReviewModule,
    AdminModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    PrismaService,
    SupplementSearchService,
    { provide: APP_FILTER, useClass: PrismaExceptionFilter },
  ],
})
export class AppModule {}
