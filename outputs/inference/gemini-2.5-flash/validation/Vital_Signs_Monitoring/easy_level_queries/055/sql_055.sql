SELECT
    STDDEV(ce.valuenum) AS sbp_stddev
FROM
    `physionet-data.mimiciv_3_1_hosp`.patients AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays AS icu
    ON p.subject_id = icu.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.chartevents AS ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
WHERE
    p.gender = 'M' -- Filter for male patients
    AND p.anchor_age BETWEEN 76 AND 86 -- Filter for age range 76-86 years
    AND ce.itemid = 220050 -- itemid for 'BP Systolic' (Systolic Blood Pressure)
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR) -- Within the first 24 hours of ICU stay
    AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
    AND ce.valuenum > 20 AND ce.valuenum < 300 -- Filter for physiologically plausible SBP values (e.g., 20-300 mmHg);