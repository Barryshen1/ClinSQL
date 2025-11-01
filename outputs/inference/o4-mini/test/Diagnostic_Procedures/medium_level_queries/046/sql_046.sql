WITH tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id   = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_version = 9
    AND d.icd_code LIKE '435%'  -- TIA
),
los_grouped AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group
  FROM
    tia_admissions
),
ct_mri_counts AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    COUNT(*) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pi.icd_code    = dp.icd_code
     AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ct%'
    OR LOWER(dp.long_title) LIKE '%mri%'
  GROUP BY
    pi.subject_id,
    pi.hadm_id
)
SELECT
  lg.los_group,
  COUNT(DISTINCT lg.subject_id) AS patient_count,
  ROUND(AVG(COALESCE(cm.proc_count, 0)), 2) AS mean_ct_mri_per_admission
FROM
  los_grouped lg
  LEFT JOIN ct_mri_counts cm
    ON lg.subject_id = cm.subject_id
   AND lg.hadm_id    = cm.hadm_id
WHERE
  lg.los_group IS NOT NULL
GROUP BY
  lg.los_group
ORDER BY
  lg.los_group;