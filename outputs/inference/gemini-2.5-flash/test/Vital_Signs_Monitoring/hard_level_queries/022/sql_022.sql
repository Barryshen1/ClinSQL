WITH cohort_patients AS (
    -- Select male ICU patients aged 85-95 with acute respiratory failure
    SELECT
        p.subject_id,
        ad.hadm_id,
        icu.stay_id,
        p.gender,
        p.anchor_age,
        icu.intime,
        icu.outtime,
        icu.los,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ad.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 85 AND 95
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.hadm_id = ad.hadm_id
                AND (
                    (di.icd_version = 9 AND di.icd_code IN ('51881')) -- Acute respiratory failure (ICD-9)
                    OR
                    (di.icd_version = 10 AND di.icd_code IN ('J9600', 'J9601', 'J9602')) -- Acute respiratory failure (ICD-10)
                )
        )
),
vital_signs_first_24hr AS (
    -- Extract relevant vital signs within the first 24 hours of ICU stay for the cohort
    SELECT
        cp.stay_id,
        ce.itemid,
        ce.valuenum
    FROM
        cohort_patients cp
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cp.stay_id = ce.stay_id
    WHERE
        ce.charttime >= cp.intime
        AND ce.charttime <= TIMESTAMP_ADD(cp.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220210, -- Respiratory Rate
            220050, -- Arterial BP Systolic
            223761, -- Temperature F
            220277  -- SpO2
        )
        AND ce.valuenum IS NOT NULL -- Only consider records with numeric values
),
instability_scores AS (
    -- Calculate the vital-sign instability score for each patient's ICU stay
    -- Score is 1 point for each vital sign measurement outside its normal range
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.stay_id,
        cp.los,
        cp.hospital_expire_flag,
        COALESCE(SUM(CASE
            WHEN (vs.itemid = 220045 AND (vs.valuenum < 60 OR vs.valuenum > 100)) THEN 1 -- HR out of range
            WHEN (vs.itemid = 220210 AND (vs.valuenum < 12 OR vs.valuenum > 20)) THEN 1 -- RR out of range
            WHEN (vs.itemid = 220050 AND (vs.valuenum < 90 OR vs.valuenum > 140)) THEN 1 -- SBP out of range
            WHEN (vs.itemid = 223761 AND (vs.valuenum < 97 OR vs.valuenum > 99)) THEN 1 -- Temp F out of range
            WHEN (vs.itemid = 220277 AND vs.valuenum < 90) THEN 1 -- SpO2 out of range
            ELSE 0
        END), 0) AS instability_score
    FROM
        cohort_patients cp
    LEFT JOIN -- Use LEFT JOIN to include patients who might not have any vital sign records in the first 24h
        vital_signs_first_24hr vs
        ON cp.stay_id = vs.stay_id
    GROUP BY
        cp.subject_id, cp.hadm_id, cp.stay_id, cp.los, cp.hospital_expire_flag
),
ranked_scores AS (
    -- Assign an instability quartile based on the instability score
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        los,
        hospital_expire_flag,
        instability_score,
        NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile -- 1 for most unstable, 4 for least
    FROM
        instability_scores
)
-- Final selection from the ranked scores
SELECT
    -- Part 1: Percentile rank of a first-24-hour vital-sign instability score of 85
    -- Calculated using the statistical definition: (count_less_than_X + 0.5 * count_equal_to_X) / total_count
    (
        SELECT
            (SUM(CASE WHEN rs_all.instability_score < 85 THEN 1 ELSE 0 END) +
             SUM(CASE WHEN rs_all.instability_score = 85 THEN 1 ELSE 0 END) * 0.5)
            / COUNT(rs_all.stay_id)
        FROM ranked_scores rs_all
    ) AS percentile_rank_for_score_85,
    -- Part 2: Average ICU length-of-stay and in-hospital mortality for the most unstable quartile
    AVG(CASE WHEN rs.instability_quartile = 1 THEN rs.los END) AS avg_los_most_unstable_quartile,
    AVG(CASE WHEN rs.instability_quartile = 1 THEN rs.hospital_expire_flag END) AS mortality_rate_most_unstable_quartile
FROM
    ranked_scores rs;