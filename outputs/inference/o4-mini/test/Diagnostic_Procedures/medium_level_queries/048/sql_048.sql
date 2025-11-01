WITH hf_admissions AS (
  -- Identify admissions of male patients aged 90-100 with at least one HF diagnosis,
  -- and classify HF as primary vs secondary per admission.
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN MAX(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' AND di.seq_num = 1 THEN 1 ELSE 0 END) = 1
        THEN 'primary'
      ELSE 'secondary'
    END AS hf_position
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
      AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(d.long_title) LIKE '%heart failure%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
),
admissions_with_los AS (
  -- Filter to LOS 1-7 days and bucket LOS
  SELECT
    *,
    CASE
      WHEN los BETWEEN 1 AND 3 THEN '1-3'
      WHEN los BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM hf_admissions
  WHERE los BETWEEN 1 AND 7
),
mri_ct_counts AS (
  -- Count MRI/CT procedures per admission
  SELECT
    pwl.hadm_id,
    pwl.los_group,
    pwl.hf_position,
    COUNT(*) AS mri_ct_count
  FROM admissions_with_los pwl
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    ON pwl.subject_id = pc.subject_id
    AND pwl.hadm_id = pc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pc.icd_code = dp.icd_code
    AND pc.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%mri%'
    OR LOWER(dp.long_title) LIKE '%ct%'
  GROUP BY
    pwl.hadm_id,
    pwl.los_group,
    pwl.hf_position
)
SELECT
  awl.los_group,
  awl.hf_position,
  COUNT(DISTINCT awl.hadm_id) AS admission_count,
  -- If an admission had zero MRI/CT, ensure it's counted as zero in the average:
  AVG(COALESCE(mcc.mri_ct_count, 0)) AS mean_mri_ct_per_admission
FROM
  admissions_with_los awl
  LEFT JOIN mri_ct_counts mcc
    ON awl.hadm_id = mcc.hadm_id
    AND awl.los_group = mcc.los_group
    AND awl.hf_position = mcc.hf_position
GROUP BY
  awl.los_group,
  awl.hf_position
ORDER BY
  awl.los_group,
  awl.hf_position;