WITH aki_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN di.seq_num = 1 THEN 'Primary AKI'
      ELSE 'Secondary AKI'
    END AS aki_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.icd_code IN ('N170', 'N171', 'N172', 'N178', 'N179') -- ICD-10 codes for AKI
),

los_stratified AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM
    aki_admissions
  WHERE
    los_days BETWEEN 1 AND 7
),

radiology_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS mri_ct_count
  FROM
    physionet-data.mimiciv_3_1_hosp.hcpcsevents h
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_hcpcs d
    ON h.hcpcs_cd = d.code
  WHERE
    LOWER(d.short_description) LIKE '%mri%' OR LOWER(d.short_description) LIKE '%ct%'
  GROUP BY
    hadm_id
)

SELECT
  l.los_group,
  l.aki_type,
  COUNT(DISTINCT l.subject_id) AS patient_count,
  AVG(COALESCE(r.mri_ct_count, 0)) AS mean_mri_ct_per_admission
FROM
  los_stratified l
LEFT JOIN
  radiology_counts r
  ON l.hadm_id = r.hadm_id
GROUP BY
  l.los_group,
  l.aki_type
ORDER BY
  l.los_group,
  l.aki_type;