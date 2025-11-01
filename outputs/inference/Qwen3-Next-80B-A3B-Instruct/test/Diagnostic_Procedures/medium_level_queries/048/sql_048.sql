WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los,
    di.seq_num,
    di.icd_code,
    di.icd_version
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '428%')
      OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
    AND EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 1 AND 7
),
imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM
    physionet-data.mimiciv_3_1_hosp.hcpcsevents h
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_hcpcs dh
    ON h.hcpcs_cd = dh.code
  WHERE
    LOWER(dh.short_description) LIKE '%ct%'
    OR LOWER(dh.short_description) LIKE '%mri%'
  GROUP BY
    h.hadm_id
)
SELECT
  CASE
    WHEN ha.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ha.los BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  CASE
    WHEN ha.seq_num = 1 THEN 'Primary'
    ELSE 'Secondary'
  END AS diagnosis_type,
  COUNT(*) AS admission_count,
  AVG(COALESCE(ic.imaging_count, 0)) AS mean_imaging_per_admission
FROM
  hf_admissions ha
LEFT JOIN
  imaging_counts ic
  ON ha.hadm_id = ic.hadm_id
GROUP BY
  los_group,
  diagnosis_type
ORDER BY
  los_group,
  diagnosis_type;