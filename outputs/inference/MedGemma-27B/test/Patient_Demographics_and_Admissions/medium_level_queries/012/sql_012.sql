WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 75 AND 85
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
), ICUStayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    AdmissionInfo AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
), DischargeCategory AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Discharged Home'
      WHEN discharge_location = 'FACILITY' THEN 'Discharged to Facility'
      WHEN deathtime IS NOT NULL THEN 'In-hospital Death'
      ELSE 'Other'
    END AS discharge_category
  FROM
    AdmissionInfo
)
SELECT
  dc.discharge_category,
  COUNT(DISTINCT CASE WHEN isi.los >= 7 THEN isi.hadm_id ELSE NULL END) AS count_los_ge_7,
  COUNT(DISTINCT isi.hadm_id) AS total_admissions,
  (COUNT(DISTINCT CASE WHEN isi.los >= 7 THEN isi.hadm_id ELSE NULL END) / COUNT(DISTINCT isi.hadm_id)) * 100 AS proportion_los_ge_7,
  PERCENTILE_CONT(isi.los, 0.5) OVER (PARTITION BY dc.discharge_category) AS median_7_day_los
FROM
  DischargeCategory AS dc
LEFT JOIN
  ICUStayInfo AS isi
  ON dc.subject_id = isi.subject_id AND dc.hadm_id = isi.hadm_id
WHERE
  isi.los IS NOT NULL
GROUP BY
  dc.discharge_category
ORDER BY
  dc.discharge_category;