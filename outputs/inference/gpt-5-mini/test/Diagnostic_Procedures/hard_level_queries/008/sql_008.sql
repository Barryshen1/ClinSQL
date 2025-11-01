WITH ugib_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE REGEXP_CONTAINS(LOWER(dd.long_title),
    r'(gastrointestinal hemorrhage|gastrointestinal haemorrhage|upper gastrointestinal|upper gi|hematemesis|haematemesis|melena|peptic ulcer with hemorrhage|hemorrhage of stomach|hemorrhage of duodenum|esophageal varices with bleeding|varices with bleeding)')
),

-- Take the first ICU stay for each admission (if multiple ICU stays per hadm exist)
first_icustays AS (
  SELECT *
  FROM (
    SELECT i.*,
           ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 48 AND 58
      AND i.hadm_id IN (SELECT hadm_id FROM ugib_admissions)
  )
  WHERE rn = 1
),

-- Count qualifying diagnostic procedures in the (calendar) first 24-hour window (DATE(intime) and next day)
proc_count_per_stay AS (
  SELECT s.stay_id,
         s.hadm_id,
         COUNT(DISTINCT pc.seq_num) AS proc_count
  FROM first_icustays s
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    ON pc.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pc.icd_code = dp.icd_code
   AND pc.icd_version = dp.icd_version
  WHERE REGEXP_CONTAINS(LOWER(dp.long_title),
        r'(endoscop|esophag|gastroscop|colonoscopy|angiograph)')
    -- approximate "first 24 hours" using chartdate on the day of ICU intime and the next calendar day
    AND pc.chartdate BETWEEN DATE(s.intime) AND DATE_ADD(DATE(s.intime), INTERVAL 1 DAY)
  GROUP BY s.stay_id, s.hadm_id
),

-- Build cohort with proc counts, LOS, and mortality flag
cohort AS (
  SELECT s.subject_id,
         s.hadm_id,
         s.stay_id,
         s.intime,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag,
         COALESCE(pc.proc_count, 0) AS proc_count,
         -- LOS in days (fractional)
         SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR), 24.0) AS los_days
  FROM first_icustays s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  LEFT JOIN proc_count_per_stay pc
    ON s.stay_id = pc.stay_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Assign quintiles by procedure count (roughly equal-sized groups)
ranked AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM cohort
)

-- Final aggregation: per quintile report average procedures, avg LOS (days), and in-hospital mortality (%)
SELECT
  quintile,
  COUNT(*) AS n,
  ROUND(AVG(proc_count), 3) AS avg_procedures_first_24h,
  ROUND(AVG(los_days), 3) AS avg_hospital_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS inhospital_mortality_percent
FROM ranked
GROUP BY quintile
ORDER BY quintile;