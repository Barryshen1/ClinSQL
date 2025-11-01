WITH
-- Admissions with mechanical ventilation procedures (ICD procedure descriptions mentioning "ventilat" or common ICD9 codes)
vent_admissions AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE (
      lower(coalesce(d.long_title, '')) LIKE '%ventilat%'  -- captures "mechanical ventilation", "ventilator", etc.
      OR p.icd_code IN ('96.70','96.71','96.72')           -- common ICD9 MV codes
    )
),

-- ICU stays that are step-down / IMC (match common name fragments)
stepdown_stays AS (
  SELECT stay_id, subject_id, hadm_id, first_careunit, last_careunit, intime, outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    (LOWER(first_careunit) LIKE '%step%' OR LOWER(last_careunit) LIKE '%step%')
    OR (LOWER(first_careunit) LIKE '%imc%' OR LOWER(last_careunit) LIKE '%imc%')
    OR (LOWER(first_careunit) LIKE '%intermediate%' OR LOWER(last_careunit) LIKE '%intermediate%')
),

-- Eligible patients: female, age between 53 and 63 (anchor_age), and admission present in vent_admissions
eligible_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON a.subject_id = pat.subject_id
  JOIN vent_admissions v
    ON a.subject_id = v.subject_id AND a.hadm_id = v.hadm_id
  WHERE LOWER(pat.gender) = 'f'
    AND pat.anchor_age BETWEEN 53 AND 63
),

-- Identify systolic BP itemids from d_items
systolic_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

-- Collect nighttime (00:00 - <06:00) systolic BP measurements that are:
--  - numeric (valuenum not null),
--  - during a step-down/IMC ICU stay,
--  - for an eligible admission (female age 53-63 with mechanical ventilation)
sbp_night AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    si.label AS item_label,
    ce.valuenum,
    ce.valueuom
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN systolic_items si
    ON ce.itemid = si.itemid
  JOIN stepdown_stays ss
    ON ce.stay_id = ss.stay_id
  JOIN eligible_admissions ea
    ON ce.hadm_id = ea.hadm_id AND ce.subject_id = ea.subject_id
  WHERE ce.valuenum IS NOT NULL
    AND (
      ce.valueuom IS NULL OR LOWER(ce.valueuom) LIKE '%mmhg%'
    )
    -- Nighttime 00:00:00 <= time < 06:00:00
    AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5
    -- Optionally ensure the charttime falls within the ICU stay window
    AND ce.charttime >= ss.intime
    AND ce.charttime < ss.outtime
)

-- Final aggregation: compute standard deviation (in mmHg) across all selected nighttime SBP measurements
SELECT
  STDDEV_POP(valuenum) AS sbp_std_mmHg,
  COUNT(*) AS n_measurements,
  COUNT(DISTINCT subject_id) AS n_patients
FROM sbp_night;