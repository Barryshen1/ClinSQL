WITH TargetICUStays AS (
    -- Step 1: Identify eligible female ED admissions aged 59-69 who had ICU stays
    SELECT
        p.subject_id,
        a.hadm_id,
        ic.stay_id,
        ic.intime,
        ic.outtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON
        p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON
        a.subject_id = ic.subject_id AND a.hadm_id = ic.hadm_id
    WHERE
        p.gender = 'F'
        AND a.admission_type = 'EMERGENCY'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
),
ICUStayMaxSBP AS (
    -- Step 2 & 3: Get all SBP readings during ICU stays and find the maximum for each stay
    SELECT
        tis.stay_id,
        MAX(ce.valuenum) AS max_sbp_icu_stay
    FROM
        TargetICUStays tis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON
        tis.subject_id = ce.subject_id AND tis.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220050, -- Arterial BP [Systolic] (Invasive)
            220179  -- Non Invasive Blood Pressure systolic
        )
        AND ce.valuenum IS NOT NULL -- Ensure value exists
        AND ce.valuenum > 0 AND ce.valuenum < 300 -- Physiological range for SBP
        AND ce.charttime BETWEEN tis.intime AND tis.outtime -- Ensure measurement is within ICU stay
    GROUP BY
        tis.stay_id
)
SELECT
    PERCENTILE_CONT(max_sbp_icu_stay, 0.75) OVER() AS sbp_75th_percentile
FROM
    ICUStayMaxSBP;