WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    -- Extract ICD-10 code for chest pain (I20.9)
    CASE
      WHEN icd_code = 'I20.9' THEN 'Chest Pain'
      ELSE NULL
    END AS admission_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`,
    UNNEST(SPLIT(REGEXP_REPLACE(icd_code, '[^0-9.]', ''), '.')) AS icd_code
  WHERE
    seq_num = 1 -- Primary diagnosis
), TnTInfo AS (
  SELECT
    labevent_id,
    subject_id,
    hadm_id,
    charttime,
    itemid,
    valuenum AS tnt_value,
    valueuom AS tnt_unit
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = 50178 -- hs-TnT itemid
), TnTInterpretation AS (
  SELECT
    labevent_id,
    CASE
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum >= 14 AND valuenum < 140 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS tnt_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = 50178 -- hs-TnT itemid
)
SELECT
  COUNT(DISTINCT tnt.subject_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN tnt.tnt_category = 'Normal' THEN tnt.subject_id END) AS normal_count,
  COUNT(DISTINCT CASE WHEN tnt.tnt_category = 'Borderline' THEN tnt.subject_id END) AS borderline_count,
  COUNT(DISTINCT CASE WHEN tnt.tnt_category = 'Myocardial Injury' THEN tnt.subject_id END) AS injury_count,
  AVG(tnt.tnt_value) AS mean_tnt,
  MEDIAN(tnt.tnt_value) AS median_tnt,
  PERCENTILE_CONT(tnt.tnt_value, 0.25) AS iqr_tnt_25,
  PERCENTILE_CONT(tnt.tnt_value, 0.75) AS iqr_tnt_75
FROM
  TnTInfo AS tnt
INNER JOIN
  PatientInfo AS p ON tnt.subject_id = p.subject_id
INNER JOIN
  AdmissionInfo AS a ON tnt.hadm_id = a.hadm_id
WHERE
  p.gender = 'M' AND p.anchor_age BETWEEN 39 AND 49 AND a.admission_diagnosis = 'Chest Pain'
GROUP BY
  tnt.tnt_category
ORDER BY
  tnt.tnt_category;