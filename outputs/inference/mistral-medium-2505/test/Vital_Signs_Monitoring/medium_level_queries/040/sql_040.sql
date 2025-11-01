WITH
-- Female patients aged 81-91
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
),

-- ICU stays with HFNC
hfnc_stays AS (
  SELECT DISTINCT c.subject_id, c.hadm_id, c.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE c.subject_id IN (SELECT subject_id FROM female_patients)
    AND LOWER(d.label) LIKE '%high flow nasal cannula%'
),

-- Mean SBP per ICU stay
mean_sbp_per_stay AS (
  SELECT
    c.stay_id,
    AVG(c.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE c.stay_id IN (SELECT stay_id FROM hfnc_stays)
    AND d.label = 'Systolic Blood Pressure'
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
)

-- Minimum mean SBP across all qualifying stays
SELECT MIN(mean_sbp) AS min_mean_sbp
FROM mean_sbp_per_stay;