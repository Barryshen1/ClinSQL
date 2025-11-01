WITH admissions_criteria AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
icu_use AS (
  SELECT 
    hadm_id,
    1 AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
imaging_procedures AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    REGEXP_CONTAINS(LOWER(d.short_description), r'ct|computed tomography|cat scan|mri|magnetic resonance')
  GROUP BY h.hadm_id
),
combined AS (
  SELECT 
    ac.hadm_id,
    ac.los_days,
    COALESCE(ip.imaging_count, 0) AS imaging_count,
    COALESCE(iu.had_icu, 0) AS had_icu
  FROM admissions_criteria ac
  LEFT JOIN icu_use iu
    ON ac.hadm_id = iu.hadm_id
  LEFT JOIN imaging_procedures ip
    ON ac.hadm_id = ip.hadm_id
)
SELECT
  CASE 
    WHEN los_days >= 1 AND los_days <= 4 THEN '1-4'
    WHEN los_days >= 5 AND los_days <= 7 THEN '5-7'
  END AS los_group,
  CASE WHEN had_icu = 1 THEN 'with ICU' ELSE 'without ICU' END AS icu_group,
  COUNT(*) AS admission_count,
  AVG(imaging_count) AS mean_imaging_per_admission
FROM combined
WHERE 
  (los_days >= 1 AND los_days <= 4) 
  OR (los_days >= 5 AND los_days <= 7)
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;