WITH hepatic_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN (
    SELECT DISTINCT di.subject_id, di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON dd.icd_code = di.icd_code
     AND dd.icd_version = di.icd_version
    WHERE LOWER(dd.long_title) LIKE '%hepatic failure%'
  ) AS hepatic_diag
    ON a.hadm_id = hepatic_diag.hadm_id
   AND a.subject_id = hepatic_diag.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 75 AND 85
),

-- Part 2: Instability proxy (first 48h) per admission using vitals from ICU chart events
instability_hep AS (
  SELECT
    h.hadm_id,
    MAX(
      CASE
        -- Heart rate
        WHEN di.label LIKE '%heart rate%' THEN
          CASE
            WHEN ce.valuenum < 60 THEN 2
            WHEN ce.valuenum <= 100 THEN 0
            WHEN ce.valuenum <= 120 THEN 1
            ELSE 2
          END
        -- Systolic / MAP
        WHEN di.label LIKE '%systolic%' OR di.label LIKE '%mean arterial pressure%' THEN
          CASE
            WHEN ce.valuenum < 90 OR ce.valuenum > 180 THEN 3
            WHEN ce.valuenum < 100 OR ce.valuenum > 160 THEN 2
            ELSE 0
          END
        -- Respiratory rate
        WHEN di.label LIKE '%respiratory%' THEN
          CASE
            WHEN ce.valuenum > 28 THEN 2
            WHEN ce.valuenum > 22 THEN 1
            ELSE 0
          END
        -- Temperature
        WHEN di.label LIKE '%temperature%' THEN
          CASE
            WHEN ce.valuenum < 36.0 OR ce.valuenum > 38.5 THEN 1
            ELSE 0
          END
        ELSE 0
      END
    ) AS max_instability
  FROM hepatic_cohort h
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= h.admittime
    AND ce.charttime <= TIMESTAMP_ADD(h.admittime, INTERVAL 2 DAY)
  GROUP BY h.hadm_id
),

death48 AS (
  SELECT
    h.hadm_id,
    CASE
      WHEN h.deathtime IS NOT NULL
           AND h.deathtime <= TIMESTAMP_ADD(h.admittime, INTERVAL 2 DAY) THEN 1
      ELSE 0
    END AS death_within_48h
  FROM hepatic_cohort h
),

los48 AS (
  SELECT
    h.hadm_id,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) AS los_days
  FROM hepatic_cohort h
),

-- Hepatic admissions with at least one critical lab value within 48h
critical_hep AS (
  SELECT DISTINCT h.hadm_id
  FROM hepatic_cohort h
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON le.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE le.charttime >= h.admittime
    AND le.charttime <= TIMESTAMP_ADD(h.admittime, INTERVAL 2 DAY)
    AND (
      (LOWER(di.label) LIKE '%creatinine%' AND le.valuenum > 4.0) OR
      (LOWER(di.label) LIKE '%bilirubin%'  AND le.valuenum > 4.0) OR
      (LOWER(di.label) LIKE '%potassium%'  AND (le.valuenum < 2.5 OR le.valuenum > 6.5)) OR
      (LOWER(di.label) LIKE '%sodium%'     AND (le.valuenum < 125 OR le.valuenum > 155)) OR
      (LOWER(di.label) LIKE '%inr%'        AND le.valuenum > 5.0) OR
      (LOWER(di.label) LIKE '%glucose%'    AND le.valuenum > 400) OR
      (LOWER(di.label) LIKE '%hemoglobin%' AND (le.valuenum < 6 OR le.valuenum > 20)) OR
      (LOWER(di.label) LIKE '%platelet%'   AND le.valuenum < 20)
    )
),

-- General admissions (all inpatients) with any critical labs within 48h
critical_all AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON le.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE le.charttime >= a.admittime
    AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 2 DAY)
    AND (
      (LOWER(di.label) LIKE '%creatinine%' AND le.valuenum > 4.0) OR
      (LOWER(di.label) LIKE '%bilirubin%'  AND le.valuenum > 4.0) OR
      (LOWER(di.label) LIKE '%potassium%'  AND (le.valuenum < 2.5 OR le.valuenum > 6.5)) OR
      (LOWER(di.label) LIKE '%sodium%'     AND (le.valuenum < 125 OR le.valuenum > 155)) OR
      (LOWER(di.label) LIKE '%inr%'        AND le.valuenum > 5.0) OR
      (LOWER(di.label) LIKE '%glucose%'    AND le.valuenum > 400) OR
      (LOWER(di.label) LIKE '%hemoglobin%' AND (le.valuenum < 6 OR le.valuenum > 20)) OR
      (LOWER(di.label) LIKE '%platelet%'   AND le.valuenum < 20)
    )
),

-- Counts for critical labs
hep_crit_count AS (
  SELECT COUNT(DISTINCT h.hadm_id) AS hepatic_crit_count
  FROM hepatic_cohort h
  JOIN critical_hep c ON c.hadm_id = h.hadm_id
),
hepacin_count AS (
  SELECT COUNT(*) AS hepatic_count
  FROM hepatic_cohort
),
general_crit_count AS (
  SELECT COUNT(DISTINCT a.hadm_id) AS general_crit_count
  FROM critical_all c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = c.hadm_id
),
total_adm AS (
  SELECT COUNT(*) AS total_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
hep_crit_rate AS (
  SELECT SAFE_DIVIDE(hc.hepatic_crit_count, hcnt.hepatic_count) AS hepatic_crit_rate
  FROM hep_crit_count hc
  CROSS JOIN hepacin_count hcnt
),
general_crit_rate AS (
  SELECT SAFE_DIVIDE(gc.general_crit_count, ta.total_adm) AS general_crit_rate
  FROM general_crit_count gc
  CROSS JOIN total_adm ta
)

-- Part 4: Final aggregation for the requested metrics
SELECT
  a_cohort.cohort_max_instability,
  a_death_hep.hepatic_mortality_48h_rate,
  a_los.hepatic_avg_los_days,
  a_hep_crit.hepatic_crit_rate,
  a_gen_crit.general_crit_rate
FROM
  (SELECT MAX(max_instability) AS cohort_max_instability
   FROM instability_hep) AS a_cohort
CROSS JOIN
  (SELECT AVG(death_within_48h) AS hepatic_mortality_48h_rate
   FROM death48) AS a_death_hep
CROSS JOIN
  (SELECT AVG(los_days) AS hepatic_avg_los_days
   FROM los48) AS a_los
CROSS JOIN
  (SELECT hepatic_crit_rate FROM hep_crit_rate) AS a_hep_crit
CROSS JOIN
  (SELECT general_crit_rate FROM general_crit_rate) AS a_gen_crit;