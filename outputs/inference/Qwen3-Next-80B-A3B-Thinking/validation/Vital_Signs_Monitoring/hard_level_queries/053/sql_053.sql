WITH icu_patients AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) BETWEEN 59 AND 69
),

shock_diagnosis AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%shock%' THEN 1 ELSE 0 END) AS shock_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY d.hadm_id
),

mortality AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

hypotension AS (
  SELECT
    c.stay_id,
    COUNTIF(c.valuenum < 65) * 1.0 / NULLIF(COUNT(*), 0) AS hypotension_burden
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_patients i ON c.stay_id = i.stay_id
  WHERE c.itemid = 52
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '24 hours'
  GROUP BY c.stay_id
),

tachycardia AS (
  SELECT
    c.stay_id,
    COUNTIF(c.valuenum > 100) * 1.0 / NULLIF(COUNT(*), 0) AS tachycardia_burden
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_patients i ON c.stay_id = i.stay_id
  WHERE c.itemid = 211
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '24 hours'
  GROUP BY c.stay_id
)

SELECT
  COALESCE(sd.shock_flag, 0) AS shock_flag,
  AVG(h.hypotension_burden) AS mean_hypotension_burden,
  APPROX_QUANTILES(h.hypotension_burden, 100)[OFFSET(25)] AS p25_hypotension_burden,
  APPROX_QUANTILES(h.hypotension_burden, 100)[OFFSET(50)] AS p50_hypotension_burden,
  APPROX_QUANTILES(h.hypotension_burden, 100)[OFFSET(75)] AS p75_hypotension_burden,
  AVG(t.tachycardia_burden) AS mean_tachycardia_burden,
  APPROX_QUANTILES(t.tachycardia_burden, 100)[OFFSET(25)] AS p25_tachycardia_burden,
  APPROX_QUANTILES(t.tachycardia_burden, 100)[OFFSET(50)] AS p50_tachycardia_burden,
  APPROX_QUANTILES(t.tachycardia_burden, 100)[OFFSET(75)] AS p75_tachycardia_burden,
  AVG(i.los) AS mean_los,
  APPROX_QUANTILES(i.los, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(i.los, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(i.los, 100)[OFFSET(75)] AS p75_los,
  AVG(m.hospital_expire_flag) AS mean_mortality,
  APPROX_QUANTILES(m.hospital_expire_flag, 100)[OFFSET(25)] AS p25_mortality,
  APPROX_QUANTILES(m.hospital_expire_flag, 100)[OFFSET(50)] AS p50_mortality,
  APPROX_QUANTILES(m.hospital_expire_flag, 100)[OFFSET(75)] AS p75_mortality,
  AVG(h.hypotension_burden + t.tachycardia_burden) AS mean_composite,
  APPROX_QUANTILES(h.hypotension_burden + t.tachycardia_burden, 100)[OFFSET(25)] AS p25_composite,
  APPROX_QUANTILES(h.hypotension_burden + t.tachycardia_burden, 100)[OFFSET(50)] AS p50_composite,
  APPROX_QUANTILES(h.hypotension_burden + t.tachycardia_burden, 100)[OFFSET(75)] AS p75_composite
FROM icu_patients i
LEFT JOIN shock_diagnosis sd ON i.hadm_id = sd.hadm_id
LEFT JOIN mortality m ON i.hadm_id = m.hadm_id
LEFT JOIN hypotension h ON i.stay_id = h.stay_id
LEFT JOIN tachycardia t ON i.stay_id = t.stay_id
GROUP BY shock_flag;