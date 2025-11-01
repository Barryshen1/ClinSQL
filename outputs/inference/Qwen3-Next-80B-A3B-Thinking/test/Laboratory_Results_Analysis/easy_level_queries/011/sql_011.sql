WITH peak_potassium AS (
  SELECT
    i.stay_id,
    MAX(l.valuenum) AS peak_k
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON i.hadm_id = l.hadm_id AND i.subject_id = l.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 56
    AND d.label = 'Potassium'
    AND l.charttime BETWEEN i.intime AND i.outtime
    AND l.valuenum IS NOT NULL
  GROUP BY
    i.stay_id
)
SELECT
  STDDEV_POP(peak_k) AS std_dev_peak_potassium
FROM
  peak_potassium;