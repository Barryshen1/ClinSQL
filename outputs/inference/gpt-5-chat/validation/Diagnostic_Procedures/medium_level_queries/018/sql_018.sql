WITH hemorrhagic_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddiag
    ON diag.icd_code = ddiag.icd_code
    AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND (
      ddiag.long_title LIKE '%hemorrhage%'
      OR ddiag.long_title LIKE '%hemorrhagic stroke%'
    )
),
ultrasound_counts AS (
  SELECT ha.hadm_id,
         DATE_DIFF(DATE(ha.dischtime), DATE(ha.admittime), DAY) AS los_days,
         COUNT(*) AS ultrasound_count
  FROM hemorrhagic_admissions AS ha
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON ha.hadm_id = proc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%ultrasound%'
  GROUP BY ha.hadm_id, los_days
),
categorized AS (
  SELECT hadm_id,
         los_days,
         ultrasound_count,
         CASE
           WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
         END AS los_category
  FROM ultrasound_counts
  WHERE los_days BETWEEN 1 AND 7
)
SELECT
  los_category,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM categorized
GROUP BY los_category
ORDER BY los_category;