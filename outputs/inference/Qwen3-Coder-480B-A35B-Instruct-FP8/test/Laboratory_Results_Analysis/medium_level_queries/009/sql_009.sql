WITH first_hstnt AS (
  SELECT
    l.hadm_id,
    l.valuenum AS first_hstnt_value
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND LOWER(d.label) LIKE '%high%'
    AND l.valuenum IS NOT NULL
    AND l.charttime IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
)

SELECT
  APPROX_QUANTILES(first_hstnt_value, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(first_hstnt_value, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(first_hstnt_value, 100)[OFFSET(75)] AS percentile_75,
  MIN(first_hstnt_value) AS min_value,
  MAX(first_hstnt_value) AS max_value
FROM
  first_hstnt
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions AS a
  ON first_hstnt.hadm_id = a.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS p
  ON a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND first_hstnt.first_hstnt_value > 0.014;