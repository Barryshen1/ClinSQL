WITH cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_dm 
    ON a.subject_id = diag_dm.subject_id AND a.hadm_id = diag_dm.hadm_id
  WHERE (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 65 AND 75
    AND p.gender = 'F'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
    AND (
      (diag_dm.icd_version = 9 AND diag_dm.icd_code LIKE '250%') OR
      (diag_dm.icd_version = 10 AND (
        diag_dm.icd_code LIKE 'E10%' OR diag_dm.icd_code LIKE 'E11%' OR 
        diag_dm.icd_code LIKE 'E12%' OR diag_dm.icd_code LIKE 'E13%' OR 
        diag_dm.icd_code LIKE 'E14%'
      ))
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
      WHERE diag_hf.subject_id = a.subject_id 
        AND diag_hf.hadm_id = a.hadm_id
        AND (
          (diag_hf.icd_version = 9 AND diag_hf.icd_code LIKE '428%') OR
          (diag_hf.icd_version = 10 AND diag_hf.icd_code LIKE 'I50%')
        )
    )
),
insulin_admins AS (
  SELECT 
    e.hadm_id,
    CASE 
      WHEN e.charttime >= a.admittime AND e.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR) THEN 'early'
      WHEN e.charttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND e.charttime <= a.dischtime THEN 'late'
    END AS period,
    MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS has_basal,
    MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS has_bolus,
    MAX(CASE WHEN insulin_type = 'sliding' THEN 1 ELSE 0 END) AS has_sliding
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.subject_id = ed.subject_id 
    AND e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON e.hadm_id = a.hadm_id
  JOIN cohort c ON a.hadm_id = c.hadm_id
  CROSS JOIN UNNEST([STRUCT(
    CASE 
      WHEN LOWER(ed.product_description) LIKE '%glargine%' 
        OR LOWER(ed.product_description) LIKE '%detemir%' 
        OR LOWER(ed.product_description) LIKE '%nph%' 
        OR LOWER(ed.product_description) LIKE '%degludec%' THEN 'basal'
      WHEN LOWER(ed.product_description) LIKE '%lispro%' 
        OR LOWER(ed.product_description) LIKE '%aspart%' 
        OR LOWER(ed.product_description) LIKE '%humalog%' 
        OR LOWER(ed.product_description) LIKE '%novolog%' 
        OR LOWER(ed.product_description) LIKE '%fiasp%' THEN 'bolus'
      WHEN LOWER(ed.product_description) LIKE '%regular%' 
        OR LOWER(ed.product_description) LIKE '%human reg%' THEN 'sliding'
    END AS insulin_type
  )]) 
  WHERE ed.administration_type = 'GIVEN'
    AND (LOWER(e.medication) LIKE '%insulin%' OR LOWER(ed.product_description) LIKE '%insulin%')
    AND insulin_type IS NOT NULL
    AND (
      (e.charttime >= a.admittime AND e.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)) OR
      (e.charttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND e.charttime <= a.dischtime)
    )
  GROUP BY e.hadm_id, period
),
period_flags AS (
  SELECT 
    hadm_id, 
    period,
    CASE 
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'basal-bolus'
      WHEN has_basal = 1 AND has_sliding = 1 THEN 'basal-bolus'
      WHEN has_bolus = 1 AND has_sliding = 1 THEN 'bolus'
      WHEN has_basal = 1 THEN 'basal'
      WHEN has_bolus = 1 THEN 'bolus'
      WHEN has_sliding = 1 THEN 'sliding-scale'
      ELSE 'none'
    END AS regimen
  FROM insulin_admins
),
regimens AS (
  SELECT 
    c.hadm_id,
    COALESCE(MAX(CASE WHEN period = 'early' THEN regimen END), 'none') AS early_regimen,
    COALESCE(MAX(CASE WHEN period = 'late' THEN regimen END), 'none') AS late_regimen
  FROM cohort c
  LEFT JOIN period_flags pf ON c.hadm_id = pf.hadm_id
  GROUP BY c.hadm_id
),
marginals AS (
  SELECT 
    early_regimen AS regimen,
    'first_48h' AS period,
    COUNTIF(early_regimen != 'none') AS num,
    COUNTIF(early_regimen != 'none') * 100.0 / (SELECT COUNT(*) FROM cohort) AS pct
  FROM regimens
  WHERE early_regimen != 'none'
  GROUP BY early_regimen
  UNION ALL
  SELECT 
    late_regimen AS regimen,
    'final_48h' AS period,
    COUNTIF(late_regimen != 'none') AS num,
    COUNTIF(late_regimen != 'none') * 100.0 / (SELECT COUNT(*) FROM cohort) AS pct
  FROM regimens
  WHERE late_regimen != 'none'
  GROUP BY late_regimen
),
transitions AS (
  SELECT 
    early_regimen AS from_regimen,
    late_regimen AS to_regimen,
    COUNT(*) AS num,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM regimens WHERE early_regimen != 'none' AND late_regimen != 'none') AS pct
  FROM regimens
  WHERE early_regimen != 'none' AND late_regimen != 'none'
  GROUP BY early_regimen, late_regimen
)
SELECT 'marginal' AS report_type, regimen AS type1, period AS type2, num, ROUND(pct, 2) AS pct
FROM marginals
UNION ALL
SELECT 'transition' AS report_type, from_regimen AS type1, to_regimen AS type2, num, ROUND(pct, 2) AS pct
FROM transitions
ORDER BY report_type, type1, type2;