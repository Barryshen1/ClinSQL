WITH diastolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic blood pressure%'
     OR LOWER(label) LIKE '%diastolic bp%'
),

-- 2) Compute per-stay maximum diastolic BP for eligible female patients aged 71-81 at admission
eligible_stays AS (
  SELECT
    icu.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN diastolic_bp_items d ON ce.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE ce.charttime BETWEEN icu.intime AND icu.outtime
    AND ce.valuenum IS NOT NULL
    AND UPPER(pat.gender) = 'F'
    -- age_at_adm = anchor_age + (admit_year - anchor_year)
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 71 AND 81
  GROUP BY icu.stay_id
)

-- 3) Median of per-stay max DBP across eligible ICUs
SELECT quantiles[OFFSET(1)] AS median_max_dbp
FROM (
  SELECT APPROX_QUANTILES(max_dbp, 2) AS quantiles
  FROM eligible_stays
);