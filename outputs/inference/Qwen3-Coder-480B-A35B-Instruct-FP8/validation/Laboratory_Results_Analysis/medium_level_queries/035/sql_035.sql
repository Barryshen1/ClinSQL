WITH first_trop AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
)

SELECT
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_length_of_stay,
  AVG(a.hospital_expire_flag) AS in_hospital_mortality
FROM
  physionet-data.mimiciv_3_1_hosp.admissions AS a
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS p
  ON a.subject_id = p.subject_id
INNER JOIN
  first_trop AS ft
  ON a.hadm_id = ft.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 73 AND 83
  AND ft.rn = 1
  AND ft.troponin_value > 0.014;