WITH first_resp_rate AS (
  SELECT
    ce.hadm_id,
    ce.valuenum AS resp_rate,
    ROW_NUMBER() OVER (PARTITION BY ce.hadm_id ORDER BY ce.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents AS ce
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items AS di
    ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'respiratory rate'
    AND ce.valuenum IS NOT NULL
)
SELECT
  STDDEV(fr.resp_rate) AS stddev_resp_rate
FROM
  physionet-data.mimiciv_3_1_hosp.patients AS p
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.admissions AS a
  ON p.subject_id = a.subject_id
INNER JOIN
  first_resp_rate AS fr
  ON a.hadm_id = fr.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 73 AND 83
  AND fr.rn = 1;