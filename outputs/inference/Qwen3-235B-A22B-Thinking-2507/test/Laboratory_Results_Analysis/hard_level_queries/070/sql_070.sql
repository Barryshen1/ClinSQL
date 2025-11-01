SELECT 
    quartile,
    'LOS' AS measure_type,
    NULL AS lab_name,
    avg_los_days AS value,
    NULL AS comparison_value
  FROM target_summary
  
  UNION ALL
  
  SELECT 
    quartile,
    'mortality' AS measure_type,
    NULL AS lab_name,
    mortality_rate AS value,
    NULL AS comparison_value
  FROM target_summary
),

-- Format the per-lab rates
per_lab_output AS (
  SELECT 
    plc.quartile,
    'abnormal_rate' AS measure_type,
    dli.label AS lab_name,
    plc.target_rate AS value,
    plc.comparison_rate AS comparison_value
  FROM per_lab_combined plc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON plc.itemid = dli.itemid
)

-- Final result: combine summary and per-lab outputs
SELECT * FROM summary_output
UNION ALL
SELECT * FROM per_lab_output
ORDER BY quartile, measure_type, lab_name;