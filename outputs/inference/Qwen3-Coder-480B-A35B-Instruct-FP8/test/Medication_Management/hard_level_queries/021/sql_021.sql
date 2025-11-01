WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag,
    adm.admittime AS admittime,
    adm.dischtime AS dischtime,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 41 AND 51
),

neutropenia AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    cohort icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON icu.hadm_id = lab.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON lab.itemid = dlab.itemid
  WHERE
    LOWER(dlab.label) = 'neutrophils'
    AND lab.valuenum < 0.5
    AND lab.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),

fever AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    cohort icu
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` chart
    ON icu.stay_id = chart.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` ditems
    ON chart.itemid = ditems.itemid
  WHERE
    LOWER(ditems.label) IN ('temperature fahrenheit', 'temperature celsius')
    AND (
      (LOWER(ditems.label) = 'temperature fahrenheit' AND chart.valuenum > 100.4) OR
      (LOWER(ditems.label) = 'temperature celsius' AND chart.valuenum > 38)
    )
    AND chart.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),

med_count AS (
  SELECT
    icu.stay_id,
    COUNT(DISTINCT pres.drug) AS unique_meds
  FROM
    cohort icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON icu.hadm_id = pres.hadm_id
  WHERE
    pres.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY
    icu.stay_id
),

qualified_stays AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    c.admittime,
    c.dischtime,
    mc.unique_meds
  FROM
    cohort c
  JOIN
    neutropenia n
    ON c.stay_id = n.stay_id
  JOIN
    fever f
    ON c.stay_id = f.stay_id
  JOIN
    med_count mc
    ON c.stay_id = mc.stay_id
),

stratified AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY unique_meds) AS med_tertile
  FROM
    qualified_stays
),

readmissions AS (
  SELECT
    s1.stay_id,
    CASE
      WHEN s2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30
  FROM
    stratified s1
  LEFT JOIN
    stratified s2
    ON s1.subject_id = s2.subject_id
    AND s2.admittime > s1.dischtime
    AND s2.admittime <= TIMESTAMP_ADD(s1.dischtime, INTERVAL 30 DAY)
)

SELECT
  s.med_tertile,
  AVG(s.los) AS avg_los_days,
  AVG(s.hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  AVG(r.readmit_30) * 100 AS readmit_30_pct
FROM
  stratified s
JOIN
  readmissions r
  ON s.stay_id = r.stay_id
GROUP BY
  s.med_tertile
ORDER BY
  s.med_tertile;