WITH first_icu AS (
  -- First ICU stay per subject (earliest intime)
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN (
    SELECT subject_id, MIN(intime) AS first_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id
  ) f
  ON i.subject_id = f.subject_id AND i.intime = f.first_intime
),
female_87_97 AS (
  SELECT fi.*
  FROM first_icu fi
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = fi.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),
bleeding_admissions AS (
  -- Admissions (first ICU stays) with lower GI bleeding
  SELECT f.subject_id, f.hadm_id, f.stay_id, f.intime, f.los
  FROM female_87_97 f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = f.subject_id AND di.hadm_id = f.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE LOWER(dd.long_title) LIKE '%lower%'
    AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%bleeding%')
),
proc_counts AS (
  -- Distinct procedures within first 48 hours of ICU stay
  SELECT ba.subject_id, ba.hadm_id, ba.stay_id,
         COUNT(DISTINCT pe.itemid) AS proc_distinct_48h
  FROM bleeding_admissions ba
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = ba.subject_id
   AND pe.hadm_id = ba.hadm_id
   AND pe.stay_id = ba.stay_id
   AND pe.starttime >= ba.intime
   AND pe.starttime <= TIMESTAMP_ADD(ba.intime, INTERVAL 48 HOUR)
  GROUP BY ba.subject_id, ba.hadm_id, ba.stay_id
),
death_indicator AS (
  -- In-hospital mortality indicator for the admission
  SELECT ba.subject_id, ba.hadm_id, ba.stay_id,
         CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hosp_mort
  FROM bleeding_admissions ba
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.subject_id = ba.subject_id AND a.hadm_id = ba.hadm_id
),
icu_los AS (
  SELECT bi.subject_id, bi.hadm_id, bi.stay_id, bi.los
  FROM bleeding_admissions bi
),
agg_base AS (
  SELECT pc.subject_id, pc.hadm_id, pc.stay_id, pc.proc_distinct_48h, il.los AS icu_los, di.in_hosp_mort
  FROM proc_counts pc
  JOIN icu_los il ON il.subject_id = pc.subject_id
                AND il.hadm_id = pc.hadm_id
                AND il.stay_id = pc.stay_id
  JOIN death_indicator di ON di.subject_id = pc.subject_id
                       AND di.hadm_id = pc.hadm_id
                       AND di.stay_id = pc.stay_id
),
quintiled AS (
  -- Assign quintiles based on the number of distinct procedures in first 48h
  SELECT ab.*,
         NTILE(5) OVER (ORDER BY proc_distinct_48h) AS quintile
  FROM agg_base ab
)
SELECT quintile,
       AVG(proc_distinct_48h) AS mean_proc_distinct_48h,
       AVG(icu_los) AS mean_icu_los_days,
       100 * AVG(in_hosp_mort) AS in_hosp_mortality_percent
FROM quintiled
GROUP BY quintile
ORDER BY quintile;