WITH `heart failure` AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS mortality,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND dd.icd_code LIKE 'I50%'
    AND dd.icd_version = 10
  ORDER BY a.admittime
  LIMIT 1
),
target_lab_instability AS (
  SELECT 
    hf.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM `heart failure` hf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hf.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hf.admittime 
        AND TIMESTAMP_ADD(hf.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE 
    (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
  GROUP BY hf.hadm_id
),
group_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
group_lab_instability AS (
  SELECT 
    ga.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM group_admissions ga
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ga.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ga.admittime 
        AND TIMESTAMP_ADD(ga.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE 
    (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
  GROUP BY ga.hadm_id
),
icu_transfers AS (
  SELECT 
    a.hadm_id,
    CASE WHEN COUNT(i.stay_id) > 0 THEN 1 ELSE 0 END AS has_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  GROUP BY a.hadm_id
),
target_data AS (
  SELECT 
    hf.hadm_id,
    COALESCE(tli.lab_instability_score, 0) AS target_lab_instability,
    hf.los AS target_los,
    hf.mortality AS target_mortality
  FROM `heart failure` hf
  LEFT JOIN target_lab_instability tli
    ON hf.hadm_id = tli.hadm_id
),
group_data AS (
  SELECT 
    ga.hadm_id,
    COALESCE(gli.lab_instability_score, 0) AS group_lab_instability,
    it.has_icu
  FROM group_admissions ga
  LEFT JOIN group_lab_instability gli
    ON ga.hadm_id = gli.hadm_id
  LEFT JOIN icu_transfers it
    ON ga.hadm_id = it.hadm_id
),
general_icu_rate AS (
  SELECT 
    SUM(has_icu) * 1.0 / COUNT(DISTINCT a.hadm_id) AS rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN icu_transfers it
    ON a.hadm_id = it.hadm_id
),
group_icu_rate AS (
  SELECT 
    SUM(has_icu) * 1.0 / COUNT(DISTINCT gd.hadm_id) AS rate
  FROM group_data gd
),
max_group_lab_instability AS (
  SELECT MAX(group_lab_instability) AS max_score
  FROM group_data
)
SELECT 
  td.target_los,
  td.target_mortality,
  mgl.max_score AS max_group_lab_instability,
  gir.rate AS rate_group,
  gir_general.rate AS rate_general
FROM target_data td
CROSS JOIN max_group_lab_instability mgl
CROSS JOIN group_icu_rate gir
CROSS JOIN general_icu_rate gir_general;