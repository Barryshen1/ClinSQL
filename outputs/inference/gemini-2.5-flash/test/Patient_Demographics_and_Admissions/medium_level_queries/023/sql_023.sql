WITH admissions_data AS ( -- Renamed the CTE to a valid identifier 'admissions_data'
    SELECT
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Categorize discharge based on hospital_expire_flag and discharge_location
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-Hospital Death'
            WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
            WHEN adm.discharge_location IN (
                'SKILLED NURSING FACILITY',
                'REHAB HOSP/FACILITY',
                'OTHER FACILITY',
                'LONG TERM CARE HOSPITAL',
                'ACUTE CARE HOSPITAL',
                'SHORT TERM HOSPITAL',
                'HOSPICE'
            ) THEN 'Facility'
            ELSE 'Other/Unknown'
        END AS discharge_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
    ON
        adm.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Male patients
        AND p.anchor_age BETWEEN 41 AND 51 -- Age between 41 and 51
        AND adm.admission_location = 'EMERGENCY ROOM' -- Admitted from the ED
        AND adm.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
        AND adm.admittime IS NOT NULL -- Ensure admit time exists for LOS calculation
)
SELECT
    discharge_category,
    ROUND(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id), 2) AS proportion_los_ge_7_days,
    -- Percentile rank of 10-day LOS, interpreted as the percentage of admissions with LOS <= 10 days
    ROUND(SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id), 2) AS percentile_rank_of_10_day_los
FROM
    admissions_data AS cohort_data -- Use the newly named CTE
GROUP BY
    discharge_category
ORDER BY
    CASE
        WHEN discharge_category = 'Home' THEN 1
        WHEN discharge_category = 'Facility' THEN 2
        WHEN discharge_category = 'In-Hospital Death' THEN 3
        ELSE 4
    END;