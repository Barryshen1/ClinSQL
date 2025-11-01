WITH ... [all CTEs] ...,
   drug_counts AS (
     SELECT 
       drug_class,
       SUM(received_first_72h) AS count_first_72h,
       SUM(received_last_72h) AS count_last_72h
     FROM cohort_summary
     WHERE drug_class IS NOT NULL
     GROUP BY drug_class
   )
   SELECT 
     d.drug_class,
     (d.count_first_72h * 100.0 / t.total_patients) AS percent_first_72h,
     (d.count_last_72h * 100.0 / t.total_patients) AS percent_last_72h
   FROM drug_counts d, total_cohort t;