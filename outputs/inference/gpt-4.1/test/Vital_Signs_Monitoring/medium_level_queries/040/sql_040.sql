WITH female_elderly AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),
hfnc_stays AS (
  -- Find ICU stays for these patients with HFNC procedure
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN female_elderly p ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON icu.subject_id = proc.subject_id
    AND icu.stay_id = proc.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON proc.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%high flow nasal cannula%'
),
sbp_items AS (
  -- Get itemids for systolic blood pressure
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(label) LIKE '%blood pressure%'
),
stay_mean_sbp AS (
  -- For each qualifying stay, calculate mean SBP
  SELECT
    h.stay_id,
    AVG(c.valuenum) AS mean_sbp
  FROM hfnc_stays h
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON h.subject_id = c.subject_id
    AND h.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM sbp_items)
    AND c.valuenum IS NOT NULL
  GROUP BY h.stay_id
)
SELECT
  MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM stay_mean_sbp;