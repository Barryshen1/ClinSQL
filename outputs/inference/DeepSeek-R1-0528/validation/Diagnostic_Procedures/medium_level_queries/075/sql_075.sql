WITH acs_diagnoses AS (
  SELECT subject_id, hadm_id, seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '411.1'))
    OR
    (icd_version = 10 AND (icd_code = 'I20.0' OR icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I23%'))
),
admissions_base AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_adm,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
),
acs_admissions AS (
  SELECT 
    ab.subject_id,
    ab.hadm_id,
    ab.los_days,
    -- Define ACS group: primary if any seq_num=1, else secondary
    CASE 
      WHEN MAX(CASE WHEN ad.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS acs_group
  FROM admissions_base ab
  INNER JOIN acs_diagnoses ad
    ON ab.subject_id = ad.subject_id AND ab.hadm_id = ad.hadm_id
  WHERE 
    ab.age_adm BETWEEN 59 AND 69
    AND ab.los_days BETWEEN 1 AND 7  -- Only 1-7 day stays
  GROUP BY ab.subject_id, ab.hadm_id, ab.los_days
),
admission_procedures AS (
  SELECT 
    aa.hadm_id,
    aa.los_days,
    aa.acs_group,
    COUNT(p.seq_num) AS procedure_count  -- Counts procedures (0 if none)
  FROM acs_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON aa.hadm_id = p.hadm_id
  GROUP BY aa.hadm_id, aa.los_days, aa.acs_group
),
admission_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM admission_procedures
)
SELECT 
  los_group,
  acs_group,
  COUNT(hadm_id) AS num_admissions,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75
FROM admission_groups
GROUP BY los_group, acs_group
ORDER BY los_group, acs_group;