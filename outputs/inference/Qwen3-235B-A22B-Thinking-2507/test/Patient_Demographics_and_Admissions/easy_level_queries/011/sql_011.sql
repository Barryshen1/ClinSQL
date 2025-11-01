WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.hadm_id IS NOT NULL
    AND a.admittime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY a.subject_id 
    ORDER BY a.admittime
  ) = 1
),
cohort AS (
  SELECT 
    fa.hadm_id,
    fa.admittime,
    fa.dischtime
  FROM first_admissions fa
  WHERE fa.gender = 'M'
    AND (fa.anchor_age - (fa.anchor_year - EXTRACT(YEAR FROM fa.admittime))) BETWEEN 76 AND 86
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = fa.hadm_id
        AND (LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%asa%')
        AND p.starttime <= fa.dischtime
        AND (p.stoptime IS NULL OR p.stoptime > fa.admittime)
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = fa.hadm_id
        AND (
          LOWER(p.drug) LIKE '%clopidogrel%' 
          OR LOWER(p.drug) LIKE '%prasugrel%' 
          OR LOWER(p.drug) LIKE '%ticagrelor%'
        )
        AND p.starttime <= fa.dischtime
        AND (p.stoptime IS NULL OR p.stoptime > fa.admittime)
    )
),
icu_los AS (
  SELECT 
    c.hadm_id,
    COALESCE(SUM(icu.los), 0) AS total_icu_los
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.hadm_id = icu.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  AVG(total_icu_los) AS avg_icu_los_days
FROM icu_los;