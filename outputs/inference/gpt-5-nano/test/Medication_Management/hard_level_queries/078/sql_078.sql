WITH QT_HOSP AS (
  SELECT 'ondansetron' AS drug UNION ALL
  SELECT 'ziprasidone' UNION ALL
  SELECT 'haloperidol' UNION ALL
  SELECT 'erythromycin' UNION ALL
  SELECT 'moxifloxacin' UNION ALL
  SELECT 'levofloxacin' UNION ALL
  SELECT 'ciprofloxacin' UNION ALL
  SELECT 'clarithromycin' UNION ALL
  SELECT 'azithromycin'
),
BLEED_HOSP AS (
  SELECT 'warfarin' AS drug UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'apixaban' AS drug UNION ALL
  SELECT 'rivaroxaban' UNION ALL
  SELECT 'edoxaban' UNION ALL
  SELECT 'dabigatran' UNION ALL
  SELECT 'clopidogrel' UNION ALL
  SELECT 'aspirin' UNION ALL
  SELECT 'ibuprofen' UNION ALL
  SELECT 'naproxen'
),
-- ICU item label lookups
QT_LABELS_ICU AS (
  SELECT 'ondansetron' AS label UNION ALL
  SELECT 'ziprasidone' UNION ALL
  SELECT 'haloperidol' UNION ALL
  SELECT 'erythromycin' UNION ALL
  SELECT 'moxifloxacin' UNION ALL
  SELECT 'levofloxacin' UNION ALL
  SELECT 'ciprofloxacin' UNION ALL
  SELECT 'clarithromycin' UNION ALL
  SELECT 'azithromycin'
),
BLEED_LABELS_ICU AS (
  SELECT 'warfarin' AS label UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'apixaban' AS label UNION ALL
  SELECT 'rivaroxaban' UNION ALL
  SELECT 'edoxaban' UNION ALL
  SELECT 'dabigatran' UNION ALL
  SELECT 'clopidogrel' UNION ALL
  SELECT 'aspirin' UNION ALL
  SELECT 'ibuprofen' UNION ALL
  SELECT 'naproxen'
),
-- 1) Hospital-based population and 24h meds
HospBase AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),
HospMedCounts AS (
  SELECT hb.subject_id, hb.hadm_id,
         COUNT(DISTINCT pr.drug) AS med_count
  FROM HospBase hb
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = hb.subject_id
   AND pr.hadm_id = hb.hadm_id
  AND pr.starttime >= hb.admittime
  AND pr.starttime < TIMESTAMP_ADD(hb.admittime, INTERVAL 1 DAY)
  GROUP BY hb.subject_id, hb.hadm_id
),
HospQT AS (
  SELECT hb.subject_id, hb.hadm_id,
         MAX(CASE WHEN LOWER(pr.drug) IN (SELECT drug FROM QT_HOSP) THEN 1 ELSE 0 END) AS has_qt
  FROM HospBase hb
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = hb.subject_id
   AND pr.hadm_id = hb.hadm_id
  AND pr.starttime >= hb.admittime
  AND pr.starttime < TIMESTAMP_ADD(hb.admittime, INTERVAL 1 DAY)
  GROUP BY hb.subject_id, hb.hadm_id
),
HospBleed AS (
  SELECT hb.subject_id, hb.hadm_id,
         MAX(CASE WHEN LOWER(pr.drug) IN (SELECT drug FROM BLEED_HOSP) THEN 1 ELSE 0 END) AS has_bleed
  FROM HospBase hb
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = hb.subject_id
   AND pr.hadm_id = hb.hadm_id
  AND pr.starttime >= hb.admittime
  AND pr.starttime < TIMESTAMP_ADD(hb.admittime, INTERVAL 1 DAY)
  GROUP BY hb.subject_id, hb.hadm_id
),
HospDomain AS (
  SELECT h.subject_id, h.hadm_id, h.admittime, h.dischtime, h.hospital_expire_flag,
         COALESCE(m.med_count, 0) AS med_count,
         COALESCE(q.has_qt, 0) AS has_qt,
         COALESCE(b.has_bleed, 0) AS has_bleed
  FROM HospBase h
  LEFT JOIN HospMedCounts m
    ON m.subject_id = h.subject_id AND m.hadm_id = h.hadm_id
  LEFT JOIN HospQT q
    ON q.subject_id = h.subject_id AND q.hadm_id = h.hadm_id
  LEFT JOIN HospBleed b
    ON b.subject_id = h.subject_id AND b.hadm_id = h.hadm_id
),
HospLOS AS (
  SELECT subject_id, hadm_id,
         TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 3600.0 AS los_hr,
         hospital_expire_flag AS death
  FROM HospDomain
),
HospTopQuart AS (
  SELECT PERCENTILE_CONT(los_hr, 0.75) OVER () AS q3
  FROM HospLOS
  LIMIT 1
),
HospMortality AS (
  SELECT
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS total_deaths,
    COUNT(*) AS total_admissions
  FROM HospDomain
),
-- ICU domain
ICUBase AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),
ICUMedCounts AS (
  SELECT ub.subject_id, ub.hadm_id, ub.stay_id,
         COUNT(DISTINCT ei.itemid) AS med_count
  FROM ICUBase ub
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ei
    ON ei.subject_id = ub.subject_id
   AND ei.hadm_id = ub.hadm_id
   AND ei.stay_id = ub.stay_id
  AND ei.starttime >= ub.intime
  AND ei.starttime < TIMESTAMP_ADD(ub.intime, INTERVAL 1 DAY)
  GROUP BY ub.subject_id, ub.hadm_id, ub.stay_id
),
ICU_QT AS (
  SELECT ub.subject_id, ub.hadm_id, ub.stay_id,
         MAX(CASE WHEN di_label_match.label IS NOT NULL THEN 1 ELSE 0 END) AS has_qt
  FROM ICUBase ub
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ei
    ON ei.subject_id = ub.subject_id
   AND ei.hadm_id = ub.hadm_id
   AND ei.stay_id = ub.stay_id
  AND ei.starttime >= ub.intime
  AND ei.starttime < TIMESTAMP_ADD(ub.intime, INTERVAL 1 DAY)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ei.itemid
  LEFT JOIN QT_LABELS_ICU di_label_match
    ON LOWER(di.label) LIKE CONCAT('%', LOWER(di_label_match.label), '%')
  GROUP BY ub.subject_id, ub.hadm_id, ub.stay_id
),
ICU_Bleed AS (
  SELECT ub.subject_id, ub.hadm_id, ub.stay_id,
         MAX(CASE WHEN di2_label_match.label IS NOT NULL THEN 1 ELSE 0 END) AS has_bleed
  FROM ICUBase ub
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ei
    ON ei.subject_id = ub.subject_id
   AND ei.hadm_id = ub.hadm_id
   AND ei.stay_id = ub.stay_id
  AND ei.starttime >= ub.intime
  AND ei.starttime < TIMESTAMP_ADD(ub.intime, INTERVAL 1 DAY)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di2
    ON di2.itemid = ei.itemid
  LEFT JOIN BLEED_LABELS_ICU di2_label_match
    ON LOWER(di2.label) LIKE CONCAT('%', LOWER(di2_label_match.label), '%')
  GROUP BY ub.subject_id, ub.hadm_id, ub.stay_id
),
ICUCombined AS (
  SELECT u.subject_id, u.hadm_id, u.stay_id, u.intime, u.outtime,
         COALESCE(m.med_count, 0) AS med_count,
         COALESCE(q.has_qt, 0) AS has_qt,
         COALESCE(b.has_bleed, 0) AS has_bleed
  FROM ICUBase u
  LEFT JOIN ICUMedCounts m
    ON m.subject_id = u.subject_id AND m.hadm_id = u.hadm_id AND m.stay_id = u.stay_id
  LEFT JOIN ICU_QT q
    ON q.subject_id = u.subject_id AND q.hadm_id = u.hadm_id AND q.stay_id = u.stay_id
  LEFT JOIN ICU_Bleed b
    ON b.subject_id = u.subject_id AND b.hadm_id = u.hadm_id AND b.stay_id = u.stay_id
),
-- ICULOS now includes LOS and death for each ICU stay
ICULOS AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id,
         TIMESTAMP_DIFF(icu.outtime, icu.intime, SECOND) / 3600.0 AS los_hr,
         icu.death
  FROM ICUCombined icu
),
ICUQuart AS (
  SELECT PERCENTILE_CONT(los_hr, 0.75) OVER () AS q3
  FROM ICULOS
  LIMIT 1
)

-- Final: Produce one row per domain (Hosp, ICU) with metrics
SELECT
  'Hosp' AS domain,
  AVG(h.med_count) AS med_mean,
  MIN(h.med_count) AS med_min,
  MAX(h.med_count) AS med_max,
  STDDEV_POP(h.med_count) AS med_sd,
  PERCENTILE_CONT(h.med_count, 0.25) OVER () AS med_p25,
  PERCENTILE_CONT(h.med_count, 0.5) OVER () AS med_p50,
  PERCENTILE_CONT(h.med_count, 0.75) OVER () AS med_p75,
  (PERCENTILE_CONT(h.med_count, 0.25) OVER () +
   PERCENTILE_CONT(h.med_count, 0.5) OVER () +
   PERCENTILE_CONT(h.med_count, 0.75) OVER ()) / 3 AS mean_of_percentiles,
  AVG(h.has_qt) AS qt_prev,
  AVG(h.has_bleed) AS bleed_prev,
  (SELECT top_prop FROM (
     SELECT SUM(CASE WHEN h2.los_hr >= t.q3 THEN 1 ELSE 0 END) / CAST(COUNT(*) AS FLOAT64) AS top_prop
     FROM HospLOS h2 CROSS JOIN HospTopQuart t
   )) AS top_quartile_prop,
  (SELECT mort_top FROM (
     SELECT SUM(CASE WHEN h3.los_hr >= t.q3 AND h3.death = 1 THEN 1 ELSE 0 END) /
            NULLIF(SUM(CASE WHEN h3.los_hr >= t.q3 THEN 1 ELSE 0 END), 0) AS mort_top
     FROM HospLOS h3 CROSS JOIN HospTopQuart t
   )) AS mortality_top_quartile
FROM HospDomain h
CROSS JOIN HospTopQuart t
CROSS JOIN (
  SELECT
    SUM(CASE WHEN h4.los_hr >= t.q3 THEN 1 ELSE 0 END) AS top_count
  FROM HospLOS h4
) AS _
UNION ALL
SELECT
  'ICU' AS domain,
  AVG(ic.med_count) AS med_mean,
  MIN(ic.med_count) AS med_min,
  MAX(ic.med_count) AS med_max,
  STDDEV_POP(ic.med_count) AS med_sd,
  PERCENTILE_CONT(ic.med_count, 0.25) OVER () AS med_p25,
  PERCENTILE_CONT(ic.med_count, 0.5) OVER () AS med_p50,
  PERCENTILE_CONT(ic.med_count, 0.75) OVER () AS med_p75,
  (PERCENTILE_CONT(ic.med_count, 0.25) OVER () +
   PERCENTILE_CONT(ic.med_count, 0.5) OVER () +
   PERCENTILE_CONT(ic.med_count, 0.75) OVER ()) / 3 AS mean_of_percentiles,
  AVG(ic.has_qt) AS qt_prev,
  AVG(ic.has_bleed) AS bleed_prev,
  (SELECT top_prop FROM (
     SELECT SUM(CASE WHEN ic2.los_hr >= t.q3 THEN 1 ELSE 0 END) / CAST(COUNT(*) AS FLOAT64) AS top_prop
     FROM ICULOS ic2 CROSS JOIN ICUQuart t
   )) AS top_quartile_prop,
  (SELECT mort_top FROM (
     SELECT SUM(CASE WHEN ic3.los_hr >= t.q3 AND ic3.death = 1 THEN 1 ELSE 0 END) /
            NULLIF(SUM(CASE WHEN ic3.los_hr >= t.q3 THEN 1 ELSE 0 END), 0) AS mort_top
     FROM ICULOS ic3 CROSS JOIN ICUQuart t
   )) AS mortality_top_quartile
FROM ICUCombined ic
LIMIT 1;