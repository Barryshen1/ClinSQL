WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
), ICUStays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
), VitalSigns AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.charttime,
    v.itemid,
    v.valuenum AS sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS v
  WHERE
    v.itemid = 220177 -- SBP itemid
), MaxSBPFirst24h AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MAX(vs.sbp) AS max_sbp
  FROM
    ICUStays AS icu
  JOIN
    VitalSigns AS vs ON icu.subject_id = vs.subject_id AND icu.hadm_id = vs.hadm_id AND icu.stay_id = vs.stay_id
  WHERE
    vs.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
), StrokeDiagnosis AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%stroke%'
    OR di.long_title LIKE '%cerebrovascular accident%'
)
SELECT
  CASE
    WHEN ms.max_sbp < 130 THEN '<130'
    WHEN ms.max_sbp BETWEEN 130 AND 139 THEN '130–139'
    WHEN ms.max_sbp BETWEEN 140 AND 159 THEN '140–159'
    ELSE '≥160'
  END AS sbp_category,
  COUNT(DISTINCT ms.subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN sd.subject_id IS NOT NULL THEN ms.subject_id ELSE NULL END) AS stroke_count,
  (COUNT(DISTINCT CASE WHEN sd.subject_id IS NOT NULL THEN ms.subject_id ELSE NULL END) / COUNT(DISTINCT ms.subject_id)) * 100 AS stroke_rate
FROM
  MaxSBPFirst24h AS ms
JOIN
  PatientInfo AS pi ON ms.subject_id = pi.subject_id
JOIN
  ICUStays AS icu ON ms.subject_id = icu.subject_id AND ms.hadm_id = icu.hadm_id AND ms.stay_id = icu.stay_id
LEFT JOIN
  StrokeDiagnosis AS sd ON ms.subject_id = sd.subject_id AND ms.hadm_id = sd.hadm_id
WHERE
  pi.gender = 'F' AND pi.anchor_age BETWEEN 70 AND 80
GROUP BY
  sbp_category
ORDER BY
  CASE
    WHEN sbp_category = '<130' THEN 1
    WHEN sbp_category = '130–139' THEN 2
    WHEN sbp_category = '140–159' THEN 3
    WHEN sbp_category = '≥160' THEN 4
  END;