WITH first_icustay AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) = 1
),

-- 2) Eligible patients: male, age 74-84, with UGIB diagnosis during this admission
eligible AS (
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    fi.intime
  FROM first_icustay AS fi
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = fi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = fi.subject_id
  WHERE (LOWER(p.gender) IN ('m', 'male'))
    AND p.anchor_age BETWEEN 74 AND 84
    -- UGIB inclusion: diagnoses long_title indicates upper GI bleeding
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS Did
        ON di.icd_code = Did.icd_code AND di.icd_version = Did.icd_version
      WHERE di.subject_id = fi.subject_id
        AND di.hadm_id = fi.hadm_id
        AND LOWER(Did.long_title) LIKE '%upper gastrointestinal bleeding%'
    )
),

-- 3) Diagnostic intensity: count of lab tests within first 72 hours of ICU intime
diag_intensity AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    COUNT(l.labevent_id) AS diag_intensity
  FROM eligible AS e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = e.subject_id
   AND l.hadm_id = e.hadm_id
   AND l.charttime >= e.intime
   AND l.charttime < TIMESTAMP_ADD(e.intime, INTERVAL 72 HOUR)
  GROUP BY e.subject_id, e.hadm_id, e.stay_id
),

-- 4) Procedure count within first 72 hours (ICU module)
proc_intensity AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    COUNT(pe.starttime) AS proc_count
  FROM eligible AS e
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.subject_id = e.subject_id
   AND pe.hadm_id = e.hadm_id
   AND pe.stay_id = e.stay_id
   AND pe.starttime >= e.intime
   AND pe.starttime < TIMESTAMP_ADD(e.intime, INTERVAL 72 HOUR)
  GROUP BY e.subject_id, e.hadm_id, e.stay_id
),

-- 5) Hospital LOS for the admission associated with the first ICU stay
los AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = e.hadm_id
),

-- 6) In-hospital mortality flag for the admission
death AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    CAST(a.hospital_expire_flag AS INT64) AS hospital_expire_flag
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = e.hadm_id
)

-- 7) Compute quartiles by diagnostic intensity and report the requested metrics per quartile
SELECT
  quartile AS quartile,
  AVG(proc_count) AS mean_proc_count,
  AVG(hosp_los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS INT64)) AS in_hospital_mortality
FROM (
  SELECT
    di.diag_intensity,
    NTILE(4) OVER (ORDER BY COALESCE(di.diag_intensity, 0)) AS quartile,
    COALESCE(pi.proc_count, 0) AS proc_count,
    lo.hosp_los_days,
    da.hospital_expire_flag
  FROM eligible AS e
  LEFT JOIN diag_intensity AS di
    ON di.subject_id = e.subject_id
   AND di.hadm_id = e.hadm_id
   AND di.stay_id = e.stay_id
  LEFT JOIN proc_intensity AS pi
    ON pi.subject_id = e.subject_id
   AND pi.hadm_id = e.hadm_id
   AND pi.stay_id = e.stay_id
  LEFT JOIN los AS lo
    ON lo.subject_id = e.subject_id
   AND lo.hadm_id = e.hadm_id
   AND lo.stay_id = e.stay_id
  LEFT JOIN death AS da
    ON da.subject_id = e.subject_id
   AND da.hadm_id = e.hadm_id
) t
GROUP BY quartile
ORDER BY quartile;