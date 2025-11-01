WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '288.0%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'D70%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '780.6%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'R50%')
        )
    )
),
med_counts AS (
  SELECT 
    c.hadm_id, 
    COUNT(DISTINCT pres.drug) AS unique_meds
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres 
    ON c.hadm_id = pres.hadm_id
    AND pres.starttime >= c.admittime
    AND pres.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),
cohort_with_meds AS (
  SELECT 
    c.*, 
    COALESCE(m.unique_meds, 0) AS unique_meds
  FROM cohort c
  LEFT JOIN med_counts m 
    ON c.hadm_id = m.hadm_id
),
tertiles AS (
  SELECT *, 
    NTILE(3) OVER (ORDER BY unique_meds ASC) AS tertile
  FROM cohort_with_meds
),
readmits AS (
  SELECT 
    t.*, 
    CASE 
      WHEN t.hospital_expire_flag = 0 
        AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
          WHERE a2.subject_id = t.subject_id 
            AND a2.hadm_id != t.hadm_id
            AND a2.admittime > t.dischtime
            AND a2.admittime <= TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY)
        ) 
      THEN 1 
      ELSE 0 
    END AS readmit_flag
  FROM tertiles t
)
SELECT 
  tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(
    SAFE_DIVIDE(
      SUM(readmit_flag) * 100.0, 
      SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)
    ), 2
  ) AS readmission_30d_pct
FROM readmits
GROUP BY tertile
ORDER BY tertile;