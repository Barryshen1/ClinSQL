WITH DischargePlatelets AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.dischtime,
    l.value AS platelet_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l ON a.hadm_id = l.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d ON l.itemid = d.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 87
    AND d.label = 'Platelet count'
    AND DATE(a.dischtime) = DATE(l.charttime)
)
SELECT
  PERCENTILE_CONT(0.75, platelet_count) AS percentile_75
FROM
  DischargePlatelets;