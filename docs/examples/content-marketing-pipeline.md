---
layout: example
title: Content Marketing Pipeline
description: Complete content marketing workflow from research to publication using specialized AI agents
---

# Content Marketing Pipeline

This example demonstrates a complete content marketing pipeline that takes a topic from initial research through to ready-to-publish content. Multiple specialized agents collaborate to create high-quality, SEO-optimized content with supporting materials.

## Overview

Our content marketing pipeline includes:
- **Market research** and trend analysis
- **SEO keyword research** and strategy
- **Content creation** with multiple formats
- **Visual content planning** and recommendations
- **Social media adaptation** for multiple platforms
- **Performance optimization** and analytics setup

## Complete Implementation

```ruby
require 'rcrewai'
require 'json'
require 'yaml'

# Configure RCrewAI for content creation
RCrewAI.configure do |config|
  config.llm_provider = :openai
  config.temperature = 0.7  # Higher creativity for content creation
end

# ===== CONTENT MARKETING CREW SETUP =====

# Market Research Specialist
market_researcher = RCrewAI::Agent.new(
  name: "market_researcher",
  role: "Content Marketing Research Specialist",
  goal: "Identify trending topics, audience interests, and competitive content gaps",
  backstory: "You are a data-driven content strategist with deep knowledge of market trends, audience behavior, and competitive analysis. You excel at identifying content opportunities that drive engagement and conversions.",
  tools: [
    RCrewAI::Tools::WebSearch.new(max_results: 15),
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# SEO Specialist
seo_specialist = RCrewAI::Agent.new(
  name: "seo_specialist",
  role: "SEO Content Strategist", 
  goal: "Optimize content for search engines while maintaining readability and value",
  backstory: "You are an SEO expert who understands how to balance search engine optimization with user experience. You excel at keyword research, content structure, and technical SEO best practices.",
  tools: [
    RCrewAI::Tools::WebSearch.new(max_results: 20),
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Content Writer
content_writer = RCrewAI::Agent.new(
  name: "content_writer",
  role: "Senior Content Writer",
  goal: "Create engaging, valuable content that connects with target audiences",
  backstory: "You are a versatile content writer with expertise across multiple formats and industries. You excel at translating complex topics into accessible, engaging content that drives action.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new,
    RCrewAI::Tools::WebSearch.new(max_results: 10)
  ],
  verbose: true
)

# Social Media Strategist
social_media_expert = RCrewAI::Agent.new(
  name: "social_media_strategist",
  role: "Social Media Content Specialist",
  goal: "Adapt content for optimal performance across social media platforms",
  backstory: "You are a social media expert who understands platform-specific best practices, audience behavior, and content formats that drive engagement across LinkedIn, Twitter, Facebook, and Instagram.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Visual Content Planner
visual_planner = RCrewAI::Agent.new(
  name: "visual_content_planner",
  role: "Visual Content Strategy Specialist",
  goal: "Plan visual elements that enhance content engagement and comprehension",
  backstory: "You are a visual content strategist who understands how images, infographics, and multimedia enhance content performance. You excel at planning visual elements that support and amplify written content.",
  tools: [
    RCrewAI::Tools::FileReader.new,
    RCrewAI::Tools::FileWriter.new
  ],
  verbose: true
)

# Create content marketing crew
content_crew = RCrewAI::Crew.new("content_marketing_pipeline")

# Add agents to crew
content_crew.add_agent(market_researcher)
content_crew.add_agent(seo_specialist)
content_crew.add_agent(content_writer)
content_crew.add_agent(social_media_expert)
content_crew.add_agent(visual_planner)

# ===== PIPELINE TASKS DEFINITION =====

# Phase 1: Market Research
market_research_task = RCrewAI::Task.new(
  name: "market_research",
  description: "Conduct comprehensive market research on AI automation in business. Identify current trends, audience pain points, competitor content gaps, and emerging opportunities. Analyze what topics are resonating with target audiences and identify unique angles.",
  expected_output: "Market research report with trend analysis, audience insights, competitor gaps, and recommended content angles with supporting data",
  agent: market_researcher,
  async: true
)

# Phase 2: SEO Strategy
seo_strategy_task = RCrewAI::Task.new(
  name: "seo_keyword_strategy",
  description: "Develop comprehensive SEO strategy based on market research findings. Identify primary and secondary keywords, analyze search intent, assess keyword difficulty, and create content structure recommendations for maximum search visibility.",
  expected_output: "SEO strategy document with keyword clusters, search volumes, competition analysis, and content structure recommendations",
  agent: seo_specialist,
  context: [market_research_task],
  async: true
)

# Phase 3: Content Creation
content_creation_task = RCrewAI::Task.new(
  name: "content_creation",
  description: "Create comprehensive blog post about AI automation in business based on market research and SEO strategy. Include introduction, main content sections, practical examples, actionable insights, and compelling conclusion. Optimize for both search engines and reader engagement.",
  expected_output: "Complete blog post (2000+ words) with SEO optimization, engaging headlines, practical examples, and clear value proposition",
  agent: content_writer,
  context: [market_research_task, seo_strategy_task]
)

# Phase 4: Social Media Adaptation
social_adaptation_task = RCrewAI::Task.new(
  name: "social_media_adaptation",
  description: "Adapt the main content for optimal performance across social media platforms. Create platform-specific versions for LinkedIn, Twitter, Facebook, and Instagram. Include appropriate hashtags, calls-to-action, and engagement strategies.",
  expected_output: "Platform-specific social media content packages with posts, captions, hashtags, and engagement strategies for each platform",
  agent: social_media_expert,
  context: [content_creation_task],
  async: true
)

# Phase 5: Visual Content Planning
visual_planning_task = RCrewAI::Task.new(
  name: "visual_content_planning",
  description: "Plan comprehensive visual content strategy to support the written content. Design specifications for featured images, infographics, social media graphics, and supplementary visual elements. Include style guidelines and platform-specific requirements.",
  expected_output: "Visual content plan with detailed specifications, design briefs, and platform-optimized visual recommendations",
  agent: visual_planner,
  context: [content_creation_task, social_adaptation_task]
)

# Add tasks to crew
content_crew.add_task(market_research_task)
content_crew.add_task(seo_strategy_task)
content_crew.add_task(content_creation_task)
content_crew.add_task(social_adaptation_task)
content_crew.add_task(visual_planning_task)

# ===== CONTENT BRIEF INPUT =====

content_brief = {
  "topic" => "AI Automation in Business",
  "target_audience" => "Business owners, entrepreneurs, and decision-makers looking to implement AI solutions",
  "primary_goal" => "Generate leads for AI consulting services",
  "secondary_goals" => [
    "Establish thought leadership in AI automation",
    "Drive website traffic and engagement",
    "Build email list through content downloads"
  ],
  "brand_voice" => "Professional yet approachable, data-driven, solution-focused",
  "content_pillars" => [
    "AI implementation strategies",
    "Business process optimization", 
    "ROI and cost-benefit analysis",
    "Real-world case studies"
  ],
  "distribution_channels" => [
    "Company blog",
    "LinkedIn",
    "Twitter", 
    "Email newsletter",
    "Industry publications"
  ],
  "success_metrics" => [
    "Organic traffic increase",
    "Social media engagement",
    "Lead generation",
    "Email sign-ups"
  ]
}

# Save content brief for agents to reference
File.write("content_brief.json", JSON.pretty_generate(content_brief))

puts "📋 Content Marketing Pipeline Starting"
puts "="*50
puts "Topic: #{content_brief['topic']}"
puts "Target Audience: #{content_brief['target_audience']}"
puts "Primary Goal: #{content_brief['primary_goal']}"
puts "Distribution Channels: #{content_brief['distribution_channels'].join(', ')}"
puts "="*50

# ===== EXECUTE CONTENT PIPELINE =====

puts "\n🚀 Executing Content Marketing Pipeline"

# Execute the complete pipeline
results = content_crew.execute

# ===== PIPELINE RESULTS ANALYSIS =====

puts "\n📊 CONTENT PIPELINE RESULTS"
puts "="*50

puts "Overall Success Rate: #{results[:success_rate]}%"
puts "Total Tasks: #{results[:total_tasks]}"
puts "Completed Tasks: #{results[:completed_tasks]}"
puts "Pipeline Status: #{results[:success_rate] >= 80 ? 'SUCCESS' : 'NEEDS REVIEW'}"

puts "\n📋 PIPELINE STAGE BREAKDOWN:"
puts "-"*40

pipeline_stages = {
  "market_research" => "📊 Market Research",
  "seo_keyword_strategy" => "🔍 SEO Strategy", 
  "content_creation" => "✍️ Content Creation",
  "social_media_adaptation" => "📱 Social Adaptation",
  "visual_content_planning" => "🎨 Visual Planning"
}

results[:results].each do |task_result|
  task_name = task_result[:task].name
  stage_name = pipeline_stages[task_name] || task_name
  status_emoji = task_result[:status] == :completed ? "✅" : "❌"
  
  puts "#{status_emoji} #{stage_name}"
  puts "   Agent: #{task_result[:assigned_agent] || task_result[:task].agent.name}"
  puts "   Status: #{task_result[:status]}"
  
  if task_result[:status] == :completed
    word_count = task_result[:result].split.length
    puts "   Output: #{word_count} words generated"
  else
    puts "   Error: #{task_result[:error]&.message}"
  end
  puts
end

# ===== SAVE CONTENT DELIVERABLES =====

puts "\n💾 SAVING CONTENT MARKETING DELIVERABLES"
puts "-"*40

completed_tasks = results[:results].select { |r| r[:status] == :completed }

# Create content package directory structure
content_package_dir = "content_marketing_package_#{Date.today.strftime('%Y%m%d')}"
Dir.mkdir(content_package_dir) unless Dir.exist?(content_package_dir)

deliverables = {}

completed_tasks.each do |task_result|
  task_name = task_result[:task].name
  content = task_result[:result]
  
  case task_name
  when "market_research"
    filename = "#{content_package_dir}/01_market_research_report.md"
    deliverables[:market_research] = filename
    
  when "seo_keyword_strategy"
    filename = "#{content_package_dir}/02_seo_strategy.md"
    deliverables[:seo_strategy] = filename
    
  when "content_creation"
    filename = "#{content_package_dir}/03_main_blog_post.md"
    deliverables[:main_content] = filename
    
  when "social_media_adaptation"
    filename = "#{content_package_dir}/04_social_media_content.md"
    deliverables[:social_content] = filename
    
  when "visual_content_planning"
    filename = "#{content_package_dir}/05_visual_content_plan.md"
    deliverables[:visual_plan] = filename
  end
  
  # Create formatted deliverable
  formatted_content = <<~CONTENT
    # #{pipeline_stages[task_name] || task_name.split('_').map(&:capitalize).join(' ')}
    
    **Generated by:** #{task_result[:assigned_agent] || task_result[:task].agent.name}  
    **Date:** #{Time.now.strftime('%B %d, %Y')}  
    **Pipeline:** Content Marketing Pipeline
    
    ---
    
    #{content}
    
    ---
    
    **Content Brief Reference:**
    - Topic: #{content_brief['topic']}
    - Target Audience: #{content_brief['target_audience']}
    - Brand Voice: #{content_brief['brand_voice']}
    
    *Generated by RCrewAI Content Marketing Pipeline*
  CONTENT
  
  File.write(filename, formatted_content)
  puts "  ✅ #{File.basename(filename)}"
end

# ===== CONTENT PACKAGE MANIFEST =====

manifest = {
  "content_package" => {
    "topic" => content_brief['topic'],
    "generated_date" => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
    "pipeline_success_rate" => results[:success_rate],
    "deliverables" => deliverables,
    "metrics" => {
      "total_content_pieces" => completed_tasks.length,
      "total_words" => completed_tasks.sum { |t| t[:result].split.length },
      "estimated_reading_time" => "#{(completed_tasks.sum { |t| t[:result].split.length } / 250.0).ceil} minutes",
      "platforms_covered" => ["Blog", "LinkedIn", "Twitter", "Facebook", "Instagram"]
    }
  }
}

File.write("#{content_package_dir}/content_manifest.json", JSON.pretty_generate(manifest))
puts "  ✅ content_manifest.json"

# ===== CONTENT PERFORMANCE TRACKING SETUP =====

tracking_setup = <<~TRACKING
  # Content Performance Tracking Setup
  
  ## Analytics Implementation
  
  ### Google Analytics 4 Events
  ```javascript
  // Blog post engagement tracking
  gtag('event', 'blog_engagement', {
    'article_title': 'AI Automation in Business',
    'content_group1': 'AI Automation',
    'engagement_time_msec': engagement_time
  });
  
  // Social media click tracking
  gtag('event', 'social_click', {
    'platform': platform_name,
    'content_type': 'blog_promotion',
    'article_title': 'AI Automation in Business'
  });
  ```
  
  ### UTM Parameters for Social Sharing
  - **LinkedIn**: `?utm_source=linkedin&utm_medium=social&utm_campaign=ai_automation_content`
  - **Twitter**: `?utm_source=twitter&utm_medium=social&utm_campaign=ai_automation_content`
  - **Facebook**: `?utm_source=facebook&utm_medium=social&utm_campaign=ai_automation_content`
  - **Email**: `?utm_source=email&utm_medium=newsletter&utm_campaign=ai_automation_content`
  
  ## Success Metrics Dashboard
  
  ### Week 1 Targets
  - Blog page views: 500+
  - Social media engagement: 50+ interactions
  - Email sign-ups: 25+
  - Average time on page: 3+ minutes
  
  ### Month 1 Targets  
  - Organic search traffic: 200+ sessions
  - Backlinks generated: 5+
  - Lead conversions: 10+
  - Content shares: 100+
  
  ## A/B Testing Plan
  
  ### Email Subject Lines
  - A: "How AI Automation Is Transforming Business Operations"
  - B: "The Ultimate Guide to Business AI Implementation"
  
  ### Social Media Headlines
  - A: Focus on ROI and cost savings
  - B: Focus on efficiency and time savings
  
  ### Call-to-Action Variations
  - A: "Download Free AI Assessment Tool"
  - B: "Get Your Custom AI Strategy Session"
  
  ## Content Amplification Strategy
  
  ### Phase 1: Organic Distribution (Week 1)
  - Publish on company blog
  - Share across all social platforms
  - Include in email newsletter
  - Submit to relevant communities
  
  ### Phase 2: Paid Promotion (Week 2-3)
  - LinkedIn Sponsored Content
  - Google Ads for high-intent keywords
  - Facebook/Instagram promotion to lookalike audiences
  
  ### Phase 3: Outreach & PR (Week 3-4)
  - Industry publication submissions
  - Influencer outreach
  - Podcast appearance pitches
  - Guest posting opportunities
TRACKING

File.write("#{content_package_dir}/06_performance_tracking.md", tracking_setup)
puts "  ✅ 06_performance_tracking.md"

# ===== CONTENT CALENDAR INTEGRATION =====

content_calendar = {
  "content_schedule" => {
    "main_blog_post" => {
      "publish_date" => (Date.today + 2).strftime('%Y-%m-%d'),
      "platform" => "Company Blog",
      "time" => "09:00 AM EST"
    },
    "social_media_rollout" => {
      "linkedin_announcement" => {
        "date" => (Date.today + 2).strftime('%Y-%m-%d'),
        "time" => "10:00 AM EST"
      },
      "twitter_thread" => {
        "date" => (Date.today + 2).strftime('%Y-%m-%d'),
        "time" => "02:00 PM EST"
      },
      "facebook_post" => {
        "date" => (Date.today + 3).strftime('%Y-%m-%d'),
        "time" => "11:00 AM EST"
      },
      "instagram_carousel" => {
        "date" => (Date.today + 3).strftime('%Y-%m-%d'),
        "time" => "05:00 PM EST"
      }
    },
    "email_newsletter" => {
      "date" => (Date.today + 7).strftime('%Y-%m-%d'),
      "time" => "10:00 AM EST",
      "segment" => "AI Interested Subscribers"
    },
    "follow_up_content" => {
      "case_study" => (Date.today + 14).strftime('%Y-%m-%d'),
      "webinar" => (Date.today + 21).strftime('%Y-%m-%d'),
      "email_series" => (Date.today + 30).strftime('%Y-%m-%d')
    }
  }
}

File.write("#{content_package_dir}/content_calendar.json", JSON.pretty_generate(content_calendar))
puts "  ✅ content_calendar.json"

# ===== FINAL PIPELINE SUMMARY =====

summary_report = <<~SUMMARY
  # Content Marketing Pipeline - Execution Summary
  
  **Topic:** #{content_brief['topic']}  
  **Execution Date:** #{Time.now.strftime('%B %d, %Y')}  
  **Pipeline Success Rate:** #{results[:success_rate]}%
  
  ## Content Package Delivered
  
  ✅ **Market Research Report** - #{deliverables[:market_research] ? 'Generated' : 'Missing'}  
  ✅ **SEO Strategy & Keywords** - #{deliverables[:seo_strategy] ? 'Generated' : 'Missing'}  
  ✅ **Main Blog Post** - #{deliverables[:main_content] ? 'Generated' : 'Missing'}  
  ✅ **Social Media Content** - #{deliverables[:social_content] ? 'Generated' : 'Missing'}  
  ✅ **Visual Content Plan** - #{deliverables[:visual_plan] ? 'Generated' : 'Missing'}  
  ✅ **Performance Tracking Setup** - Generated  
  ✅ **Content Calendar** - Generated
  
  ## Content Metrics
  
  - **Total Words Generated:** #{completed_tasks.sum { |t| t[:result].split.length }.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}
  - **Estimated Reading Time:** #{(completed_tasks.sum { |t| t[:result].split.length } / 250.0).ceil} minutes
  - **Content Pieces Created:** #{completed_tasks.length}
  - **Platforms Covered:** 5 (Blog, LinkedIn, Twitter, Facebook, Instagram)
  
  ## Agent Performance
  
  #{content_crew.agents.map do |agent|
    assigned_tasks = completed_tasks.select do |task|
      (task[:assigned_agent] || task[:task].agent.name) == agent.name
    end
    
    if assigned_tasks.any?
      total_words = assigned_tasks.sum { |t| t[:result].split.length }
      "- **#{agent.name}** (#{agent.role}): #{assigned_tasks.length} task(s), #{total_words} words"
    end
  end.compact.join("\n")}
  
  ## Next Steps
  
  ### Immediate Actions (Next 24 Hours)
  1. Review all generated content for brand consistency
  2. Create visual assets based on visual content plan
  3. Set up tracking pixels and UTM parameters
  4. Schedule social media posts in management tool
  
  ### Week 1 Actions
  1. Publish main blog post with SEO optimizations
  2. Execute social media rollout according to calendar
  3. Begin email marketing sequence
  4. Monitor initial performance metrics
  
  ### Week 2-4 Actions
  1. Analyze performance data and optimize
  2. Create follow-up content based on engagement
  3. Reach out to industry publications
  4. Plan next content in the series
  
  ## ROI Projections
  
  Based on similar content campaigns:
  - **Estimated Reach:** 5,000+ people
  - **Projected Engagement:** 300+ interactions  
  - **Expected Leads:** 25-50 qualified prospects
  - **Estimated Value:** $15,000-$30,000 in pipeline
  
  ## Content Amplification Opportunities
  
  - Industry publications and guest posting
  - Podcast appearances and interviews  
  - Speaking opportunities at conferences
  - Partnership with complementary brands
  - Influencer collaboration possibilities
  
  ---
  
  **Content Package Location:** `#{content_package_dir}/`  
  **Ready for Review:** Yes  
  **Ready for Publication:** After final review and visual asset creation
  
  *This comprehensive content marketing package was generated by RCrewAI's automated content pipeline, saving an estimated 20-25 hours of manual work while ensuring consistent quality and SEO optimization.*
SUMMARY

File.write("#{content_package_dir}/PIPELINE_SUMMARY.md", summary_report)

puts "\n🎉 CONTENT MARKETING PIPELINE COMPLETED!"
puts "="*60
puts "📁 Complete content package saved to: #{content_package_dir}/"
puts ""
puts "📊 **Pipeline Results:**"
puts "   • Success Rate: #{results[:success_rate]}%"
puts "   • Content Pieces: #{completed_tasks.length}"
puts "   • Total Words: #{completed_tasks.sum { |t| t[:result].split.length }.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
puts "   • Platforms Ready: 5 (Blog + Social Media)"
puts ""
puts "🚀 **Ready for Publication:**"
puts "   • Main blog post optimized and ready"
puts "   • Social media content adapted for each platform"
puts "   • Visual content specifications provided"
puts "   • Performance tracking configured"
puts "   • Content calendar scheduled"
puts ""
puts "💡 **Estimated Time Saved:** 20-25 hours of manual content creation"
puts "💰 **Projected ROI:** $15,000-$30,000 in pipeline value"
```

## Key Pipeline Features

### 1. **Multi-Agent Collaboration**
Each agent specializes in a specific aspect of content marketing:

```ruby
market_researcher    # Trend analysis and audience research
seo_specialist      # Keyword strategy and optimization  
content_writer      # Main content creation
social_media_expert # Platform-specific adaptation
visual_planner      # Visual content strategy
```

### 2. **Dependency-Based Workflow**
Tasks execute in logical order with proper dependencies:

```ruby
# Research feeds into SEO strategy
seo_strategy_task.context = [market_research_task]

# Both research and SEO inform content creation
content_creation_task.context = [market_research_task, seo_strategy_task]

# Content feeds into social and visual planning
social_adaptation_task.context = [content_creation_task]
visual_planning_task.context = [content_creation_task, social_adaptation_task]
```

### 3. **Complete Content Package**
The pipeline generates everything needed for content marketing success:

- Market research and trend analysis
- SEO-optimized main content
- Platform-specific social media versions
- Visual content specifications
- Performance tracking setup
- Content calendar with scheduling

### 4. **Performance Tracking**
Built-in analytics and optimization setup:

```ruby
# UTM parameters for tracking
# A/B testing plans
# Success metrics dashboard
# Content amplification strategy
```

## Content Marketing Patterns

### Research-Driven Creation
```ruby
Market Research → SEO Strategy → Content Creation

# Ensures content is data-driven and strategically aligned
```

### Multi-Platform Optimization
```ruby
Main Content → Social Adaptation → Visual Planning

# Maximizes reach across all distribution channels
```

### Performance-First Approach
```ruby
Content Creation → Tracking Setup → Amplification Strategy

# Ensures measurable ROI and continuous optimization
```

## Scaling the Pipeline

### Adding Content Types
```ruby
# Add specialized agents for different content formats
video_producer = RCrewAI::Agent.new(
  name: "video_content_producer",
  role: "Video Content Strategist",
  goal: "Create engaging video content strategies"
)

podcast_producer = RCrewAI::Agent.new(
  name: "podcast_producer", 
  role: "Podcast Content Specialist",
  goal: "Develop podcast content and show formats"
)
```

### Industry Customization
```ruby
# Customize for specific industries
healthcare_content_crew = content_crew.clone
healthcare_content_crew.add_agent(compliance_specialist)
healthcare_content_crew.add_agent(medical_writer)
```

### Multi-Language Support
```ruby
# Add translation and localization
translator = RCrewAI::Agent.new(
  name: "content_translator",
  role: "Content Localization Specialist", 
  goal: "Adapt content for international markets"
)
```

This content marketing pipeline provides a comprehensive, automated solution for creating high-quality, multi-platform content that drives engagement and conversions while saving significant time and ensuring consistent quality.