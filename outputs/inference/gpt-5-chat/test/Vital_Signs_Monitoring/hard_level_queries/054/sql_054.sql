WITH cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id,
         pat.gender, pat.anchor_age, adm.hospital_expire_flag,
         icu.los,
         icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code
   AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND LOWER(d_diag.long_title) LIKE '%acute respiratory failure%'
),
vitals AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
         di.label,
         ce.charttime,
         ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label IN ('Mean Arterial Pressure', 'Heart Rate')
    AND ce.valuenum IS NOT NULL
),
first72h AS (
  SELECT v.subject_id, v.hadm_id, v.stay_id,
         v.label,
         v.valuenum
  FROM vitals v
  JOIN cohort c
    ON v.stay_id = c.stay_id
  WHERE v.charttime >= c.intime
    AND v.charttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
),
burdens AS (
  SELECT
    subject_id, hadm_id, stay_id,
    SAFE_DIVIDE(SUM(CASE WHEN label = 'Mean Arterial Pressure' AND valuenum < 65 THEN 1 ELSE 0 END),
                SUM(CASE WHEN label = 'Mean Arterial Pressure' THEN 1 ELSE 0 END)
               ) AS map_burden,
    SAFE_DIVIDE(SUM(CASE WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END),
                SUM(CASE WHEN label = 'Heart Rate' THEN 1 ELSE 0 END)
               ) AS hr_burden
  FROM first72h
  GROUP BY subject_id, hadm_id, stay_id
),
composite AS (
  SELECT b.subject_id, b.hadm_id, b.stay_id,
         b.map_burden, b.hr_burden,
         (b.map_burden + b.hr_burden) AS composite_score,
         c.los,
         c.hospital_expire_flag
  FROM burdens b
  JOIN cohort c
    ON b.stay_id = c.stay_id
),
summary_cohort AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS p75,
    (APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] -
     APPROX_QUANTILES(composite_score, 100)[OFFSET(25)]) AS iqr,
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM composite
),
general_icu AS (
  SELECT gi.subject_id, gi.hadm_id, gi.stay_id,
         SAFE_DIVIDE(SUM(CASE WHEN label = 'Mean Arterial Pressure' AND valuenum < 65 THEN 1 ELSE 0 END),
                     SUM(CASE WHEN label = 'Mean Arterial Pressure' THEN 1 ELSE 0 END)
                    ) AS map_burden,
         SAFE_DIVIDE(SUM(CASE WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END),
                     SUM(CASE WHEN label = 'Heart Rate' THEN 1 ELSE 0 END)
                    ) AS hr_burden,
         icu.los,
         adm.hospital_expire_flag
  FROM (
    SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
           di.label,
           ce.charttime,
           ce.valuenum,
           icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ce.stay_id = icu.stay_id
    WHERE di.label IN ('Mean Arterial Pressure', 'Heart Rate')
      AND ce.valuenum IS NOT NULL
      AND ce.charttime >= icu.intime
      AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  ) gi
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON gi.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON gi.hadm_id = adm.hadm_id
  GROUP BY gi.subject_id, gi.hadm_id, gi.stay_id, icu.los, adm.hospital_expire_flag
),
summary_general AS (
  SELECT
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM general_icu
)
SELECT
  sc.*, sg.avg_map_burden AS general_avg_map_burden,
  sg.avg_hr_burden AS general_avg_hr_burden,
  sg.avg_los AS general_avg_los,
  sg.mortality_rate AS general_mortality_rate
FROM summary_cohort sc
CROSS JOIN summary_general sg;