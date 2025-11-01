with pneumonia (aspiration vs community-acquired), provide in-hospital mortality (%) by LOS (1–3/4–7/≥8 days) and day-1 ICU status; report absolute/relative differences and average comorbidity count.
-- It stratifies the results by hospital length of stay (LOS), day-1 ICU status, and pneumonia type (Aspiration vs. Community-Acquired).
-- The final output includes patient counts, average comorbidity counts, mortality rates, and the absolute/relative differences in mortality between pneumonia types.

WITH
-- CTE 1: Select the base cohort of male patients aged 39-49 at admission.
patient_base AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        -- Calculate age at admission and filter
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 39 AND 49
),

-- CTE 2: Identify pneumonia diagnoses and prioritize Aspiration pneumonia if both types are present.
pneumonia_dx AS (
    SELECT
        hadm_id,
        pneumonia_type
    FROM (
        SELECT
            hadm_id,
            CASE
                WHEN icd_code IN ('5070', 'J690') THEN 'Aspiration'
                WHEN icd_code IN ('486', 'J189') THEN 'Community-Acquired'
            END AS pneumonia_type,
            -- Use ROW_NUMBER to assign a single pneumonia type per admission, prioritizing Aspiration
            ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY
                CASE
                    WHEN icd_code IN ('5070', 'J690') THEN 1 -- Priority 1
                    WHEN icd_code IN ('486', 'J189') THEN 2 -- Priority 2
                END
            ) as rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
            icd_code IN ('5070', 'J690', '486', 'J189')
            AND icd_version IN (9, 10)
    ) AS ranked_dx
    WHERE rn = 1
),

-- CTE 3: Calculate a comorbidity count for each admission, excluding the pneumonia diagnosis itself.
comorbidity_count AS (
    SELECT
        hadm_id,
        COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Exclude the primary pneumonia diagnoses to count only other conditions
        icd_code NOT IN ('5070', 'J690', '486', 'J189')
    GROUP BY
        hadm_id
),

-- CTE 4: Identify admissions with an ICU stay within the first 24 hours.
day1_icu AS (
    SELECT DISTINCT
        icu.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    WHERE
        icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
),

-- CTE 5: Combine all features for the final cohort of pneumonia patients.
cohort_features AS (
    SELECT
        pb.hadm_id,
        pb.hospital_expire_flag,
        pdx.pneumonia_type,
        cc.comorbidity_count,
        -- Use a more precise LOS calculation based on hours for accurate binning
        CASE
            WHEN DATETIME_DIFF(pb.dischtime, pb.admittime, HOUR) / 24.0 <= 3 THEN '1-3 days'
            WHEN DATETIME_DIFF(pb.dischtime, pb.admittime, HOUR) / 24.0 <= 7 THEN '4-7 days'
            ELSE '>=8 days'
        END AS los_group,
        CASE
            WHEN d1i.hadm_id IS NOT NULL THEN 'ICU on Day 1'
            ELSE 'No ICU on Day 1'
        END AS day1_icu_status
    FROM
        patient_base AS pb
    INNER JOIN
        pneumonia_dx AS pdx ON pb.hadm_id = pdx.hadm_id
    LEFT JOIN
        comorbidity_count AS cc ON pb.hadm_id = cc.hadm_id
    LEFT JOIN
        day1_icu AS d1i ON pb.hadm_id = d1i.hadm_id
    WHERE
        pb.dischtime IS NOT NULL -- Ensure LOS can be calculated
),

-- CTE 6: Aggregate statistics for each stratum before pivoting.
grouped_stats AS (
    SELECT
        los_group,
        day1_icu_status,
        pneumonia_type,
        COUNT(hadm_id) AS num_patients,
        SUM(hospital_expire_flag) AS num_deaths,
        AVG(COALESCE(comorbidity_count, 0)) AS avg_comorbidity_count
    FROM
        cohort_features
    GROUP BY
        los_group,
        day1_icu_status,
        pneumonia_type
)

-- Final step: Pivot the results to compare pneumonia types and calculate differences.
SELECT
    los_group,
    day1_icu_status,

    -- Community-Acquired Pneumonia Metrics
    MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_patients ELSE 0 END) AS community_patients,
    ROUND(MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN avg_comorbidity_count END), 2) AS community_avg_comorbidity,
    ROUND(SAFE_DIVIDE(
        MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_deaths END) * 100.0,
        MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_patients END)
    ), 2) AS community_mortality_pct,

    -- Aspiration Pneumonia Metrics
    MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN num_patients ELSE 0 END) AS aspiration_patients,
    ROUND(MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN avg_comorbidity_count END), 2) AS aspiration_avg_comorbidity,
    ROUND(SAFE_DIVIDE(
        MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN num_deaths END) * 100.0,
        MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN num_patients END)
    ), 2) AS aspiration_mortality_pct,

    -- Difference Calculations
    ROUND(
        SAFE_DIVIDE(MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN num_deaths END) * 100.0, MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN num_patients END))
        -
        SAFE_DIVIDE(MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_deaths END) * 100.0, MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_patients END))
    , 2) AS absolute_mortality_diff_pct,

    ROUND(SAFE_DIVIDE(
        (
            SAFE_DIVIDE(MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN num_deaths END) * 100.0, MAX(CASE WHEN pneumonia_type = 'Aspiration' THEN num_patients END))
            -
            SAFE_DIVIDE(MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_deaths END) * 100.0, MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_patients END))
        ),
        SAFE_DIVIDE(MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_deaths END) * 100.0, MAX(CASE WHEN pneumonia_type = 'Community-Acquired' THEN num_patients END))
    ) * 100, 2) AS relative_mortality_diff_pct
FROM
    grouped_stats
GROUP BY
    los_group,
    day1_icu_status
ORDER BY
    day1_icu_status DESC, -- ICU patients first
    CASE
        WHEN los_group = '1-3 days' THEN 1
        WHEN los_group = '4-7 days' THEN 2
        WHEN los_group = '>=8 days' THEN 3
    END;