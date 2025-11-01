WITH
-- 1. ARDS male inpatients aged 71-81
ards_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
     AND a.hadm_id   = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dc
      ON d.icd_code    = dc.icd_code
     AND d.icd_version = dc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND LOWER(dc.long_title) LIKE '%acute respiratory distress syndrome%'
),

-- 2. ICU stays for that cohort, with 72h window end
icu_72h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    LEAST(icu.outtime, TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)) AS window_end
  FROM
    ards_cohort AS c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON c.subject_id = icu.subject_id
     AND c.hadm_id   = icu.hadm_id
),

-- 3. Compute instability score per patient in first 72h
instability_events AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    COUNTIF(
      (di.label = 'Heart Rate'                  AND ce.valuenum > 100)
      OR (di.label = 'Respiratory Rate'         AND ce.valuenum > 20)
      OR (di.label = 'O2 saturation'            AND ce.valuenum < 90)
      OR (di.label = 'Arterial BP [Systolic]'   AND ce.valuenum < 90)
    ) AS instability_score
  FROM
    icu_72h AS i
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ce.subject_id = i.subject_id
     AND ce.stay_id    = i.stay_id
     AND ce.charttime BETWEEN i.intime AND i.window_end
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  GROUP BY
    i.subject_id,
    i.hadm_id,
    i.stay_id
),

-- 4. 90th percentile threshold
pct90 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS thr
  FROM
    instability_events
),

-- 5. High-instability patients
high_instab AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.instability_score
  FROM
    instability_events AS ie
    CROSS JOIN pct90
  WHERE
    ie.instability_score >= pct90.thr
),

-- 6a. Outcomes for high-instability group
high_outcomes AS (
  SELECT
    hi.subject_id,
    hi.hadm_id,
    ar.hospital_expire_flag,
    ic.los,
    SAFE_DIVIDE(COUNTIF(l.flag = 'abnormal'), COUNT(*)) AS lab_abn_rate
  FROM
    high_instab AS hi
    JOIN ards_cohort AS ar
      ON hi.subject_id = ar.subject_id
     AND hi.hadm_id    = ar.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON hi.subject_id = ic.subject_id
     AND hi.stay_id     = ic.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON hi.subject_id = l.subject_id
     AND hi.hadm_id     = l.hadm_id
     AND l.charttime BETWEEN ic.intime
                       AND LEAST(ic.outtime, TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR))
  GROUP BY
    hi.subject_id,
    hi.hadm_id,
    ar.hospital_expire_flag,
    ic.los
),

-- 7. General comparator: male aged 71-81 inpatients
gen_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients`   AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

gen_lab_rate AS (
  SELECT
    gc.subject_id,
    gc.hadm_id,
    SAFE_DIVIDE(COUNTIF(l.flag = 'abnormal'), COUNT(*)) AS lab_abn_rate
  FROM
    gen_cohort AS gc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON gc.subject_id = l.subject_id
     AND gc.hadm_id     = l.hadm_id
  GROUP BY
    gc.subject_id,
    gc.hadm_id
)

-- Final aggregation and reporting via scalar subqueries
SELECT
  (SELECT thr FROM pct90)                                                AS instability_90th_pct,
  (SELECT AVG(hospital_expire_flag) FROM high_outcomes)                   AS mortality_rate,
  (SELECT AVG(los)                 FROM high_outcomes)                   AS mean_icu_los_days,
  (SELECT AVG(lab_abn_rate)        FROM high_outcomes)                   AS high_instab_lab_abn_rate,
  (SELECT AVG(lab_abn_rate)        FROM gen_lab_rate)                    AS general_lab_abn_rate;