WITH mortality_rates AS (
  SELECT
    los_category,
    charlson_category,
    sepsis_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate
  FROM final_data
  GROUP BY los_category, charlson_category, sepsis_group
)
SELECT
  m1.los_category,
  m1.charlson_category,
  m1.mortality_rate AS mortality_rate_sepsis_without_shock,
  m2.mortality_rate AS mortality_rate_septic_shock,
  ROUND(m2.mortality_rate - m1.mortality_rate, 2) AS absolute_difference,
  ROUND(m2.mortality_rate / NULLIF(m1.mortality_rate, 0), 2) AS relative_difference
FROM mortality_rates m1
FULL OUTER JOIN mortality_rates m2
  ON m1.los_category = m2.los_category
  AND m1.charlson_category = m2.charlson_category
  AND m1.sepsis_group = 'sepsis_without_shock'
  AND m2.sepsis_group = 'septic_shock'
ORDER BY m1.los_category, m1.charlson_category;