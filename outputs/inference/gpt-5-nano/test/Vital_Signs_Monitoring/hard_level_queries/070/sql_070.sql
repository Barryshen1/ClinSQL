WITH eligible AS (
  SELECT icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = icu.subject_id
        AND di.hadm_id = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%hyperosmolar%'
    )
),

-- 24-hour HR, MAP, RR sums for each eligible icustay
sums AS (
  SELECT e.stay_id,
         SUM(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum ELSE 0 END) AS hr_sum24,
         SUM(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%arterial pressure%' THEN ce.valuenum ELSE 0 END) AS map_sum24,
         SUM(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN ce.valuenum ELSE 0 END) AS rr_sum24
  FROM eligible e
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON icu.stay_id = e.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
  WHERE ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY e.stay_id
),

-- 24h stay instability score (std dev of all included vitals)
instab AS (
  SELECT e.stay_id, STDDEV_SAMP(ce.valuenum) AS instability_score
  FROM eligible e
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON icu.stay_id = e.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
  WHERE ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%respiratory rate%')
  GROUP BY e.stay_id
),

-- abnormal vital count within 24h window
abn AS (
  SELECT e.stay_id, COUNT(*) AS abnormal_vital_count
  FROM eligible e
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON icu.stay_id = e.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
  WHERE ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND di.lownormalvalue IS NOT NULL AND di.highnormalvalue IS NOT NULL
    AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue)
  GROUP BY e.stay_id
)

-- Base per-stay table with computed metrics
, cv_base AS (
  SELECT e.stay_id,
         (COALESCE(s.hr_sum24, 0) + COALESCE(s.map_sum24, 0) + COALESCE(s.rr_sum24, 0)) AS cv_sum24_total,
         icu.los AS icu_los,
         a.hospital_expire_flag AS hosp_expire,
         i.instability_score,
         abn.abnormal_vital_count
  FROM eligible e
  LEFT JOIN sums s ON s.stay_id = e.stay_id
  LEFT JOIN instab i ON i.stay_id = e.stay_id
  LEFT JOIN abn abn ON abn.stay_id = e.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON icu.stay_id = e.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = icu.hadm_id
)

-- Add decile and percentile threshold, then filter to top quartile
, cv_with_decile AS (
  SELECT cvb.*,
         NTILE(10) OVER (ORDER BY cvb.cv_sum24_total DESC) AS decile_10
  FROM cv_base cvb
)
, cv_with_p75 AS (
  SELECT cwd.*,
         PERCENTILE_CONT(0.75) OVER (ORDER BY cv_sum24_total) AS p75
  FROM cv_with_decile cwd
)

SELECT
  cwp.stay_id,
  cwp.cv_sum24_total,
  cwp.decile_10,
  cwp.instability_score,
  cwp.abnormal_vital_count,
  cwp.icu_los,
  CASE WHEN cwp.hosp_expire = 1 THEN 1 ELSE 0 END AS in_hospital_mortality
FROM cv_with_p75 cwp
WHERE cwp.cv_sum24_total >= cwp.p75
ORDER BY cwp.cv_sum24_total DESC;