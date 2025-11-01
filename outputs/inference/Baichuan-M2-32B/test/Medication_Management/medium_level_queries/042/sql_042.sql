SELECT
  COUNT(*) AS total_patients,
  SUM(CASE WHEN first_48h_insulin = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_first_48h_insulin,
  SUM(CASE WHEN first_48h_oral_agent = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_first_48h_oral_agent,
  SUM(CASE WHEN final_24h_insulin = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_final_24h_insulin,
  SUM(CASE WHEN final_24h_oral_agent = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_final_24h_oral_agent,
  SUM(insulin_continued) AS insulin_continued_count,
  SUM(insulin_initiated) AS insulin_initiated_count,
  SUM(insulin_discontinued) AS insulin_discontinued_count,
  SUM(oral_agent_continued) AS oral_agent_continued_count,
  SUM(oral_agent_initiated) AS oral_agent_initiated_count,
  SUM(oral_agent_discontinued) AS oral_agent_discontinued_count
FROM final_output;