WITH hf_diag AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    MAX(CASE
          WHEN di.seq_num = 1
               AND (
                    (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
                    (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                   )
          THEN 1 ELSE 0
        END) AS primary_hf,
    MAX(CASE
          WHEN (
                    (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
                    (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
               )
          THEN 1 ELSE 0
        END) AS any_hf
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
),
hf_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    CASE
      WHEN primary_hf = 1 THEN 'Primary HF'
      WHEN any_hf = 1 THEN 'Secondary HF'
      ELSE NULL
    END AS hf_status,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM hf_diag
  WHERE primary_hf = 1 OR any_hf = 1
),
imaging_counts AS (
  SELECT p.subject_id, p.hadm_id, COUNT(*) AS mri_ct_ct
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%mri%' OR LOWER(d.long_title) LIKE '%ct%'
  GROUP BY p.subject_id, p.hadm_id
)
SELECT
  t.hf_status,
  t.los_bucket,
  COUNT(*) AS admission_count,
  AVG(COALESCE(t.mri_ct_ct, 0)) AS mean_mri_ct_per_admission
FROM (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hf_status,
    a.los_days,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_bucket,
    COALESCE(ic.mri_ct_ct, 0) AS mri_ct_ct
  FROM hf_admissions a
  LEFT JOIN imaging_counts ic
    ON a.subject_id = ic.subject_id
   AND a.hadm_id = ic.hadm_id
) t
WHERE t.los_bucket IS NOT NULL
GROUP BY t.hf_status, t.los_bucket
ORDER BY t.hf_status, t.los_bucket;