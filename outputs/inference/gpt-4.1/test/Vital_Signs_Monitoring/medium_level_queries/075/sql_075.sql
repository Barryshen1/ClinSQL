WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.subject_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 56 AND 66
),
map_measurements AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE
    ce.itemid IN (220045, 225312) -- MAP itemids
    AND ce.valuenum IS NOT NULL
),
stay_map AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    c.subject_id,
    AVG(m.valuenum) AS mean_map
  FROM
    cohort c
  JOIN
    map_measurements m
    ON c.stay_id = m.stay_id
  GROUP BY
    c.stay_id, c.hadm_id, c.subject_id
),
stroke_stays AS (
  SELECT DISTINCT
    s.stay_id
  FROM
    stay_map s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.hadm_id = d.hadm_id
  WHERE
    (
      -- ICD-9 stroke codes
      (d.icd_version = 9 AND (
        REGEXP_CONTAINS(d.icd_code, r'^430') OR
        REGEXP_CONTAINS(d.icd_code, r'^431') OR
        REGEXP_CONTAINS(d.icd_code, r'^433[0-9]1') OR
        REGEXP_CONTAINS(d.icd_code, r'^434[0-9]1') OR
        REGEXP_CONTAINS(d.icd_code, r'^436')
      ))
      OR
      -- ICD-10 stroke codes
      (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^I60') OR
        REGEXP_CONTAINS(d.icd_code, r'^I61') OR
        REGEXP_CONTAINS(d.icd_code, r'^I63')
      ))
    )
),
final AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.mean_map,
    CASE
      WHEN s.mean_map < 65 THEN '<65'
      WHEN s.mean_map >= 65 AND s.mean_map < 75 THEN '65–74'
      WHEN s.mean_map >= 75 AND s.mean_map < 85 THEN '75–84'
      WHEN s.mean_map >= 85 THEN '≥85'
      ELSE 'Unknown'
    END AS map_category,
    IF(st.stay_id IS NOT NULL, 1, 0) AS stroke
  FROM
    stay_map s
  LEFT JOIN
    stroke_stays st
    ON s.stay_id = st.stay_id
)
SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS stay_count,
  SUM(stroke) AS stroke_count,
  ROUND(SUM(stroke) / COUNT(*), 4) AS stroke_rate
FROM
  final
GROUP BY
  map_category
ORDER BY
  -- Order by MAP category in clinical order
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65–74' THEN 2
    WHEN '75–84' THEN 3
    WHEN '≥85' THEN 4
    ELSE 5
  END;