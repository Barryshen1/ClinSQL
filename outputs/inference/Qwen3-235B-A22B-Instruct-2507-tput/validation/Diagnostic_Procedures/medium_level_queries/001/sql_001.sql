WITH acs_codes AS (
  SELECT 'I21' AS icd_code, 10 AS icd_version
  UNION ALL SELECT 'I22', 10
  UNION ALL SELECT 'I20.0', 10
),
imaging_codes AS (
  SELECT code FROM UNNEST([
    '70450','70460','70470','70480','70490','70492',  -- CT Head
    '71250','71260','71270','71271','71272',          -- CT Chest
    '74150','74170','74175','74176','74177','74178',  -- CT Abdomen
    '72191','72192','72193','72194',                  -- CT Pelvis
    '71045','71046','71047','71048',                  -- X-ray Chest
    '74018','74019'                                   -- X-ray Abdomen
  ]) AS code
),
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE anchor_age BETWEEN 77 AND 87
),
admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
),
acs_admissions AS (
  SELECT
    di.hadm_id,
    di.subject_id,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN acs_codes acs ON di.icd_code = acs.icd_code AND di.icd_version = acs.icd_version
  WHERE di.seq_num >= 1
),
acs_with_imaging AS (
  SELECT
    aa.hadm_id,
    aa.diagnosis_type,
    a.los_days,
    COUNT(hc.hcpcs_cd) AS imaging_count
  FROM acs_admissions aa
  INNER JOIN admissions_with_los a ON aa.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents hc
    ON aa.hadm_id = hc.hadm_id
  INNER JOIN imaging_codes ic ON hc.hcpcs_cd = ic.code
  WHERE a.los_days BETWEEN 1 AND 8
  GROUP BY aa.hadm_id, aa.diagnosis_type, a.los_days
),
stratified_groups AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    diagnosis_type,
    imaging_count
  FROM acs_with_imaging
)
SELECT
  los_group,
  diagnosis_type,
  AVG(imaging_count) AS mean_imaging_count,
  MIN(imaging_count) AS min_imaging_count,
  MAX(imaging_count) AS max_imaging_count
FROM stratified_groups
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;