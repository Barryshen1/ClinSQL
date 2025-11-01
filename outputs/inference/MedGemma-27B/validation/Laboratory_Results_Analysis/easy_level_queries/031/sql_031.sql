WITH DischargePotassium AS (
  SELECT
    l.valuenum AS potassium_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu -- Corrected dataset for icustays
    ON a.hadm_id = icu.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND d.label = 'Potassium'
    AND DATE(l.charttime) = DATE(a.dischtime)
)
SELECT
  APPROX_QUANTILES(potassium_value, 0.75)[OFFSET(0)] AS p75_potassium
FROM
  DischargePotassium;