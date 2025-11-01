WITH base AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 80 AND 90
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
with_icu AS (
  SELECT 
    b.*,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu
  FROM base b
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON b.hadm_id = i.hadm_id
),
with_comorbidities AS (
  SELECT 
    w.hadm_id,
    w.hospital_expire_flag,
    w.hospital_los,
    w.has_icu,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%') 
      THEN 1 ELSE 0 
    END) AS has_ckd,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%')
        OR (d.icd_version = 10 AND (
          d.icd_code LIKE 'E08%' 
          OR d.icd_code LIKE 'E09%' 
          OR d.icd_code LIKE 'E10%' 
          OR d.icd_code LIKE 'E11%' 
          OR d.icd_code LIKE 'E13%'
        ))
      THEN 1 ELSE 0 
    END) AS has_diabetes
  FROM with_icu w
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON w.hadm_id = d.hadm_id
  GROUP BY w.hadm_id, w.hospital_expire_flag, w.hospital_los, w.has_icu
)
SELECT
  CASE WHEN has_icu = 1 THEN 'ICU' ELSE 'non-ICU' END AS icu_status,
  CASE WHEN hospital_los < 8 THEN '<8' ELSE '>=8' END AS los_category,
  COUNT(*) AS total_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(has_ckd) * 100 AS ckd_pct,
  AVG(has_diabetes) * 100 AS diabetes_pct
FROM with_comorbidities
GROUP BY icu_status, los_category
ORDER BY icu_status, los_category;