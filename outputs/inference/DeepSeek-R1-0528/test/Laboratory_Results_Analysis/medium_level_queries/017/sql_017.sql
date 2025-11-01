WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    p.anchor_age + (DATE_DIFF(DATE(adm.admittime), DATE(p.anchor_year, 1, 1), DAY) / 365.25) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
          OR 
          (diag.icd_version = 10 AND 
            (diag.icd_code LIKE 'I20%' OR 
             diag.icd_code LIKE 'I21%' OR 
             diag.icd_code LIKE 'I22%' OR 
             diag.icd_code LIKE 'I23%' OR 
             diag.icd_code LIKE 'I24%' OR 
             diag.icd_code LIKE 'I25%')
          )
        )
    )
    AND p.anchor_age + (DATE_DIFF(DATE(adm.admittime), DATE(p.anchor_year, 1, 1), DAY) / 365.25) BETWEEN 47 AND 57
),
first_troponin_cohort AS (
  SELECT 
    c.hadm_id,
    ft.troponin_value
  FROM cohort c
  INNER JOIN (
    SELECT 
      l.hadm_id,
      l.valuenum AS troponin_value,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime, l.labevent_id) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    WHERE l.itemid IN (50911, 51003)   -- Troponin T item IDs
      AND l.valuenum > 0.014           -- Exclude values <= 0.014 ng/mL
  ) ft
  ON c.hadm_id = ft.hadm_id
  WHERE ft.rn = 1  -- First Troponin-T measurement per admission
)
SELECT 
  quartiles[OFFSET(1)] AS q1,
  quartiles[OFFSET(2)] AS median,
  quartiles[OFFSET(3)] AS q3,
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(troponin_value, 4) AS quartiles
  FROM first_troponin_cohort
);