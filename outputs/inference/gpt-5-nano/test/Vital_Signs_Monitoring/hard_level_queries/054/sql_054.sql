WITH TargetCohort AS (
  SELECT i.subject_id,
         i.hadm_id,
         i.stay_id,
         i.intime,
         i.los,
         a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays AS i
  JOIN physionet-data.mimiciv_3_1_hosp.admissions AS a
    ON i.hadm_id = a.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.patients AS p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(d.long_title) LIKE '%acute respiratory failure%'
),
TargetWithLOS AS (
  SELECT t.subject_id,
         t.hadm_id,
         t.stay_id,
         t.intime,
         t.los,
         t.hospital_expire_flag
  FROM TargetCohort AS t
),
TargetBurden AS (
  SELECT t.subject_id,
         t.hadm_id,
         t.stay_id,
         t.intime,
         t.los,
         t.hospital_expire_flag,
         SUM(
           CASE
             WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%' THEN
               CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END
             ELSE 0
           END
           +
           CASE
             WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%' THEN
               CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END
             ELSE 0
           END
         ) AS burden_72h
  FROM TargetWithLOS AS t
  JOIN physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON ce.subject_id = t.subject_id
   AND ce.hadm_id = t.hadm_id
   AND ce.stay_id = t.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= t.intime
    AND ce.charttime <= TIMESTAMP_ADD(t.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY t.subject_id, t.hadm_id, t.stay_id, t.intime, t.los, t.hospital_expire_flag
),
TargetQuant AS (
  SELECT APPROX_QUANTILES(burden_72h, 4) AS q
  FROM TargetBurden
),
GeneralCohort AS (
  SELECT i.subject_id,
         i.hadm_id,
         i.stay_id,
         i.intime,
         i.los,
         a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays AS i
  JOIN physionet-data.mimiciv_3_1_hosp.admissions AS a
    ON i.hadm_id = a.hadm_id
),
GeneralWithLOS AS (
  SELECT g.subject_id,
         g.hadm_id,
         g.stay_id,
         g.intime,
         g.los,
         g.hospital_expire_flag
  FROM GeneralCohort AS g
),
GeneralBurden AS (
  SELECT g.subject_id,
         g.hadm_id,
         g.stay_id,
         g.intime,
         g.los,
         g.hospital_expire_flag,
         SUM(
           CASE
             WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%' THEN
               CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END
             ELSE 0
           END
           +
           CASE
             WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%' THEN
               CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END
             ELSE 0
           END
         ) AS burden_72h
  FROM GeneralWithLOS AS g
  JOIN physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON ce.subject_id = g.subject_id
   AND ce.hadm_id = g.hadm_id
   AND ce.stay_id = g.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= g.intime
    AND ce.charttime <= TIMESTAMP_ADD(g.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY g.subject_id, g.hadm_id, g.stay_id, g.intime, g.los, g.hospital_expire_flag
),
GeneralQuant AS (
  SELECT APPROX_QUANTILES(burden_72h, 4) AS q
  FROM GeneralBurden
)

SELECT
  'target' AS cohort,
  AVG(tb.burden_72h) AS avg_burden_72h,
  tq.q[OFFSET(1)] AS p25,
  tq.q[OFFSET(2)] AS p50,
  tq.q[OFFSET(3)] AS p75,
  tq.q[OFFSET(3)] - tq.q[OFFSET(1)] AS iqr,
  AVG(tb.los) AS avg_los,
  SUM(CASE WHEN tb.hospital_expire_flag THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS mortality_rate
FROM TargetBurden AS tb
CROSS JOIN TargetQuant AS tq

UNION ALL

SELECT
  'general' AS cohort,
  AVG(gb.burden_72h) AS avg_burden_72h,
  gq.q[OFFSET(1)] AS p25,
  gq.q[OFFSET(2)] AS p50,
  gq.q[OFFSET(3)] AS p75,
  gq.q[OFFSET(3)] - gq.q[OFFSET(1)] AS iqr,
  AVG(gb.los) AS avg_los,
  SUM(CASE WHEN gb.hospital_expire_flag THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS mortality_rate
FROM GeneralBurden AS gb
CROSS JOIN GeneralQuant AS gq;