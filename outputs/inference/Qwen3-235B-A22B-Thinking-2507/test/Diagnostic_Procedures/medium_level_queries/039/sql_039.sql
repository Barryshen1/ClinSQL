WITH asthma_exacerbation_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    LOWER(long_title) LIKE '%asthma%' 
    AND (LOWER(long_title) LIKE '%exacerbation%' OR LOWER(long_title) LIKE '%status asthmaticus%')
),
asthma_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN asthma_exacerbation_codes aec
    ON di.icd_code = aec.icd_code AND di.icd_version = aec.icd_version
),
base_cohort AS (
  SELECT 
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.hadm_id IN (SELECT hadm_id FROM asthma_admissions)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),
filtered_cohort AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
    END AS los_group
  FROM base_cohort
  WHERE los_days BETWEEN 1 AND 8
),
icu_status AS (
  SELECT 
    fc.hadm_id,
    fc.los_group,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status
  FROM filtered_cohort fc
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON fc.hadm_id = i.hadm_id
),
imaging_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%computed tomography%'
    OR LOWER(d.short_description) LIKE '%ct%'
    OR LOWER(d.long_description) LIKE '%magnetic resonance imaging%'
    OR LOWER(d.short_description) LIKE '%mri%'
  GROUP BY h.hadm_id
)
SELECT 
  icu_status.los_group,
  icu_status.icu_status,
  AVG(COALESCE(imaging_counts.imaging_count, 0)) AS mean_imaging,
  MIN(COALESCE(imaging_counts.imaging_count, 0)) AS min_imaging,
  MAX(COALESCE(imaging_counts.imaging_count, 0)) AS max_imaging
FROM icu_status
LEFT JOIN imaging_counts
  ON icu_status.hadm_id = imaging_counts.hadm_id
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;