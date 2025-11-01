WITH filtered_patients AS (
    -- Step 1: Filter patients based on age and gender
    SELECT
        p.subject_id,
        p.anchor_age,
        p.gender
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 70 AND 80
),
eligible_icu_stays AS (
    -- Step 2: Get eligible ICU stays for the filtered patients
    SELECT
        fp.subject_id,
        ics.hadm_id,
        ics.stay_id,
        ics.intime
    FROM
        filtered_patients fp
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ics
        ON fp.subject_id = ics.subject_id
),
sbp_measurements_24h AS (
    -- Step 3: Extract SBP measurements within the first 24 hours of ICU stay
    SELECT
        eis.subject_id,
        eis.hadm_id,
        eis.stay_id,
        ce.charttime,
        ce.valuenum
    FROM
        eligible_icu_stays eis
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON eis.subject_id = ce.subject_id
        AND eis.hadm_id = ce.hadm_id
        AND eis.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220050,  -- Arterial Blood Pressure systolic
            220179,  -- Non Invasive Blood Pressure systolic
            224167,  -- Arterial/CBP [Systolic]
            227242,  -- Non-invasive Blood Pressure Systolic (pulsatile)
            227702   -- BP Systolic
        )
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.charttime BETWEEN eis.intime AND DATETIME_ADD(eis.intime, INTERVAL 24 HOUR)
),
max_sbp_per_stay AS (
    -- Step 4: Find maximum SBP for each eligible ICU stay
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        MAX(valuenum) AS max_sbp
    FROM
        sbp_measurements_24h
    GROUP BY
        subject_id, hadm_id, stay_id
),
patient_highest_sbp_category AS (
    -- Step 5: For each patient, determine their single highest SBP and assign a category
    SELECT
        subject_id,
        MAX(max_sbp) AS overall_max_sbp,
        CASE
            WHEN MAX(max_sbp) < 130 THEN 'SBP < 130'
            WHEN MAX(max_sbp) BETWEEN 130 AND 139 THEN 'SBP 130-139'
            WHEN MAX(max_sbp) BETWEEN 140 AND 159 THEN 'SBP 140-159'
            ELSE 'SBP >= 160'
        END AS sbp_category
    FROM
        max_sbp_per_stay
    GROUP BY
        subject_id
),
stroke_flag_patients AS (
    -- Step 6: Identify patients with any stroke diagnosis in their record
    SELECT DISTINCT
        subject_id,
        TRUE AS had_stroke
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dio
    WHERE
        (
            (dio.icd_version = 9 AND (
                -- ICD-9 codes for stroke
                LEFT(dio.icd_code, 3) IN ('430', '431', '432', '434', '436')
                OR (LEFT(dio.icd_code, 3) = '433' AND SUBSTRING(dio.icd_code, 5, 1) = '1') -- 433.x1 means with infarction
            ))
            OR
            (dio.icd_version = 10 AND (
                -- ICD-10 codes for stroke
                LEFT(dio.icd_code, 3) IN ('I60', 'I61', 'I63')
                OR dio.icd_code = 'I64' -- I64 is 'Stroke, not specified as hemorrhage or infarction'
            ))
        )
)
-- Final Aggregation: Calculate percentages and stroke rate per SBP category
SELECT
    phsc.sbp_category,
    COUNT(DISTINCT phsc.subject_id) AS num_patients_in_category,
    SAFE_DIVIDE(COUNT(DISTINCT phsc.subject_id) * 100.0, (SELECT COUNT(DISTINCT subject_id) FROM patient_highest_sbp_category)) AS percent_patients_in_category,
    COUNT(DISTINCT CASE WHEN sfp.had_stroke THEN phsc.subject_id END) AS num_patients_with_stroke,
    SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN sfp.had_stroke THEN phsc.subject_id END) * 100.0, COUNT(DISTINCT phsc.subject_id)) AS stroke_rate_in_category
FROM
    patient_highest_sbp_category phsc
LEFT JOIN
    stroke_flag_patients sfp
    ON phsc.subject_id = sfp.subject_id
GROUP BY
    phsc.sbp_category
ORDER BY
    CASE phsc.sbp_category
        WHEN 'SBP < 130' THEN 1
        WHEN 'SBP 130-139' THEN 2
        WHEN 'SBP 140-159' THEN 3
        WHEN 'SBP >= 160' THEN 4
        ELSE 5 -- Should not happen if categories are exhaustive
    END
;