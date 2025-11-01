WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND REGEXP_CONTAINS(di.icd_code, r'^E(08|10|11|13)')
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND REGEXP_CONTAINS(di.icd_code, r'^I50')
    )
),
total_cohort AS (
  SELECT COUNT(*) AS total_admissions
  FROM cohort
),
first24_insulin AS (
  SELECT 
    c.hadm_id,
    COALESCE(MAX(CASE WHEN ph.sliding_scale IS NOT NULL AND LENGTH(TRIM(ph.sliding_scale)) > 0 THEN 1 ELSE 0 END), 0) AS has_sliding,
    COALESCE(MAX(CASE 
      WHEN LOWER(ph.medication) LIKE '%glargine%' 
        OR LOWER(ph.medication) LIKE '%detemir%' 
        OR LOWER(ph.medication) LIKE '%nph%' 
        OR LOWER(ph.medication) LIKE '%degludec%' 
        OR LOWER(ph.medication) LIKE '%isophane%' 
      THEN 1 ELSE 0 END), 0) AS has_basal,
    COALESCE(MAX(CASE 
      WHEN (LOWER(ph.medication) LIKE '%aspart%' 
            OR LOWER(ph.medication) LIKE '%lispro%' 
            OR LOWER(ph.medication) LIKE '%glulisine%' 
            OR LOWER(ph.medication) LIKE '%regular%')
        AND (ph.sliding_scale IS NULL OR LENGTH(TRIM(ph.sliding_scale)) = 0)
      THEN 1 ELSE 0 END), 0) AS has_bolus
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id 
    AND ph.hadm_id = c.hadm_id
    AND LOWER(ph.medication) LIKE '%insulin%'
    AND ph.starttime <= c.admittime + INTERVAL 24 HOUR
    AND (ph.stoptime >= c.admittime OR ph.stoptime IS NULL)
  GROUP BY c.hadm_id
),
first24_regimen AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN has_basal = 1 AND (has_bolus = 1 OR has_sliding = 1) THEN 'Basal-Bolus'
      WHEN has_basal = 1 THEN 'Basal'
      WHEN has_sliding = 1 THEN 'sliding-scale'
      WHEN has_bolus = 1 THEN 'Bolus'
      ELSE 'None'
    END AS regimen
  FROM first24_insulin
),
first_summary AS (
  SELECT 
    regimen,
    COUNTIF(regimen != 'None') AS count_first,  -- Only count the four types
    ROUND(COUNTIF(regimen != 'None') * 100.0 / (SELECT total_admissions FROM total_cohort), 2) AS percent_first
  FROM first24_regimen
  GROUP BY regimen
  HAVING regimen IN ('Basal-Bolus', 'Basal', 'Bolus', 'sliding-scale')
),
final12_insulin AS (
  SELECT 
    c.hadm_id,
    COALESCE(MAX(CASE WHEN ph.sliding_scale IS NOT NULL AND LENGTH(TRIM(ph.sliding_scale)) > 0 THEN 1 ELSE 0 END), 0) AS has_sliding,
    COALESCE(MAX(CASE 
      WHEN LOWER(ph.medication) LIKE '%glargine%' 
        OR LOWER(ph.medication) LIKE '%detemir%' 
        OR LOWER(ph.medication) LIKE '%nph%' 
        OR LOWER(ph.medication) LIKE '%degludec%' 
        OR LOWER(ph.medication) LIKE '%isophane%' 
      THEN 1 ELSE 0 END), 0) AS has_basal,
    COALESCE(MAX(CASE 
      WHEN (LOWER(ph.medication) LIKE '%aspart%' 
            OR LOWER(ph.medication) LIKE '%lispro%' 
            OR LOWER(ph.medication) LIKE '%glulisine%' 
            OR LOWER(ph.medication) LIKE '%regular%')
        AND (ph.sliding_scale IS NULL OR LENGTH(TRIM(ph.sliding_scale)) = 0)
      THEN 1 ELSE 0 END), 0) AS has_bolus
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id 
    AND ph.hadm_id = c.hadm_id
    AND LOWER(ph.medication) LIKE '%insulin%'
    AND ph.starttime <= c.dischtime
    AND (ph.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) OR ph.stoptime IS NULL)
  GROUP BY c.hadm_id
),
final12_regimen AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN has_basal = 1 AND (has_bolus = 1 OR has_sliding = 1) THEN 'Basal-Bolus'
      WHEN has_basal = 1 THEN 'Basal'
      WHEN has_sliding = 1 THEN 'sliding-scale'
      WHEN has_bolus = 1 THEN 'Bolus'
      ELSE 'None'
    END AS regimen
  FROM final12_insulin
),
final_summary AS (
  SELECT 
    regimen,
    COUNTIF(regimen != 'None') AS count_final,
    ROUND(COUNTIF(regimen != 'None') * 100.0 / (SELECT total_admissions FROM total_cohort), 2) AS percent_final
  FROM final12_regimen
  GROUP BY regimen
  HAVING regimen IN ('Basal-Bolus', 'Basal', 'Bolus', 'sliding-scale')
)
SELECT 
  COALESCE(fs.regimen, fn.regimen) AS regimen,
  COALESCE(fs.percent_first, 0) AS first24_percent,
  COALESCE(fn.percent_final, 0) AS final12_percent,
  ROUND(COALESCE(fn.percent_final, 0) - COALESCE(fs.percent_first, 0), 2) AS change_percentage_points
FROM first_summary fs
FULL OUTER JOIN final_summary fn ON fs.regimen = fn.regimen
ORDER BY 
  CASE regimen
    WHEN 'Basal-Bolus' THEN 1
    WHEN 'Basal' THEN 2
    WHEN 'Bolus' THEN 3
    WHEN 'sliding-scale' THEN 4
  END;