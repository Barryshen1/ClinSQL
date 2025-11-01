WITH admissions_with_next_event AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        pat.anchor_age,
        pat.gender,
        pat.dod,
        -- Get the next admission time for the same patient to check for readmissions
        LEAD(ad.admittime, 1) OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
),
base_population AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        dod,
        DATE_DIFF(dischtime, admittime, DAY) AS los_days,
        -- Flag for 30-day readmission: next admission within 30 days and patient didn't die before it
        CASE
            WHEN next_admittime IS NOT NULL
                 AND DATE_DIFF(next_admittime, dischtime, DAY) BETWEEN 0 AND 30
                 AND (dod IS NULL OR dod >= next_admittime)
            THEN 1 ELSE 0
        END AS readmitted_30_day
    FROM
        admissions_with_next_event
    WHERE
        gender = 'M'
        AND anchor_age BETWEEN 41 AND 51
),
-- Step 2: Identify Neutropenia in the first 48 hours
neutropenia_events AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        -- Flag if any Absolute Neutrophil Count < 1.5 K/uL in the first 48 hours
        MAX(CASE WHEN le.valuenum < 1.5 THEN 1 ELSE 0 END) AS has_neutropenia
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        base_population bp
        ON le.subject_id = bp.subject_id AND le.hadm_id = bp.hadm_id
    WHERE
        le.itemid = 51219 -- Absolute Neutrophil Count (K/uL)
        AND le.valuenum IS NOT NULL
        AND le.charttime BETWEEN bp.admittime AND DATETIME_ADD(bp.admittime, INTERVAL 48 HOUR)
    GROUP BY
        le.subject_id, le.hadm_id
),
-- Step 3: Identify Fever in the first 48 hours
fever_events AS (
    SELECT
        ce.subject_id,
        ce.hadm_id,
        -- Flag if any Temperature C >= 38.0 in the first 48 hours
        MAX(CASE WHEN ce.valuenum >= 38.0 THEN 1 ELSE 0 END) AS has_fever
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        base_population bp
        ON ce.subject_id = bp.subject_id AND ce.hadm_id = bp.hadm_id
    WHERE
        ce.itemid = 223762 -- Temperature C
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN bp.admittime AND DATETIME_ADD(bp.admittime, INTERVAL 48 HOUR)
    GROUP BY
        ce.subject_id, ce.hadm_id
),
-- Step 4: Count unique medications prescribed in the first 48 hours
med_counts AS (
    SELECT
        bp.subject_id,
        bp.hadm_id,
        COUNT(DISTINCT pm.drug) AS unique_med_count
    FROM
        base_population bp
    LEFT JOIN -- Use LEFT JOIN to include patients with 0 medications
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pm
        ON bp.subject_id = pm.subject_id
        AND bp.hadm_id = pm.hadm_id
        AND pm.starttime BETWEEN bp.admittime AND DATETIME_ADD(bp.admittime, INTERVAL 48 HOUR)
    GROUP BY
        bp.subject_id, bp.hadm_id
),
-- Step 5: Combine all criteria and assign tertiles
cohort_with_tertiles AS (
    SELECT
        bp.subject_id,
        bp.hadm_id,
        bp.los_days,
        bp.hospital_expire_flag,
        bp.readmitted_30_day,
        COALESCE(mc.unique_med_count, 0) AS unique_med_count, -- Use COALESCE to handle 0 counts from LEFT JOIN
        NTILE(3) OVER (ORDER BY COALESCE(mc.unique_med_count, 0) ASC) AS tertile_med_count
    FROM
        base_population bp
    INNER JOIN -- Filter for patients who had neutropenia
        neutropenia_events ne
        ON bp.subject_id = ne.subject_id AND bp.hadm_id = ne.hadm_id
        AND ne.has_neutropenia = 1 -- Moved this condition for clarity
    INNER JOIN -- Filter for patients who had fever
        fever_events fe
        ON bp.subject_id = fe.subject_id AND bp.hadm_id = fe.hadm_id
        AND fe.has_fever = 1 -- Moved this condition for clarity
    LEFT JOIN -- Use LEFT JOIN here to ensure all patients meeting criteria are included,
              -- even if they have no prescriptions (unique_med_count will be NULL, then COALESCE to 0)
        med_counts mc
        ON bp.subject_id = mc.subject_id AND bp.hadm_id = mc.hadm_id
)
-- Step 6: Report outcomes by tertile
SELECT
    tertile_med_count AS medication_count_tertile,
    COUNT(DISTINCT hadm_id) AS cohort_size,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS in_hospital_mortality_percent,
    ROUND(SUM(CAST(readmitted_30_day AS BIGNUMERIC)) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS readmission_30_day_percent
FROM
    cohort_with_tertiles
WHERE tertile_med_count IS NOT NULL -- Exclude cases where NTILE could return NULL if there are no rows
GROUP BY
    tertile_med_count
ORDER BY
    tertile_med_count;