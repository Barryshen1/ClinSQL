WITH medicine_hadms AS (
    -- First, identify all hospital admissions that were ever on a medicine service.
    -- This is done to efficiently filter for "medicine inpatients".
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE curr_service LIKE '%MED%'
),

cohort_los AS (
    -- Next, build the patient cohort by applying all filters and calculating LOS.
    SELECT
        a.hadm_id,
        -- Calculate Length of Stay (LOS) in fractional days for more precise statistics.
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
        -- Categorize the discharge outcome into the three requested groups.
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN a.discharge_location LIKE 'HOME%' THEN 'Home'
            WHEN a.discharge_location IN (
                'SKILLED NURSING FACILITY',
                'REHAB/DISTINCT PART HOSP',
                'CHRONIC/LONG TERM CARE',
                'HOSPICE',
                'LONG TERM CARE HOSPITAL',
                'ASSISTED LIVING',
                'ACUTEHOSP', -- Acute care hospital
                'OTHER FACILITY',
                'PSYCH FACILITY',
                'HEALTHCARE FACILITY'
            ) THEN 'Facility'
            ELSE NULL -- Other dispositions will be excluded from the final result.
        END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    -- Join to get patient demographics (gender, age).
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    -- Ensure the admission was for a medicine inpatient.
    INNER JOIN medicine_hadms AS m
        ON a.hadm_id = m.hadm_id
    WHERE
        -- Filter for female patients.
        p.gender = 'F'
        -- Filter for age at admission between 52 and 62.
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 52 AND 62
        -- Filter for non-elective admissions.
        AND a.admission_type NOT IN ('ELECTIVE', 'SURGICAL SAME DAY ADMISSION')
        -- Ensure LOS is a valid, positive duration.
        AND a.dischtime > a.admittime
)

-- Finally, group by the discharge category and calculate the required statistics.
SELECT
    discharge_category,
    COUNT(hadm_id) AS number_of_stays,
    AVG(los_days) AS mean_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
    -- Calculate the percentile rank of a 7-day LOS.
    -- This is the proportion of stays with LOS <= 7 days.
    COUNTIF(los_days <= 7) / COUNT(los_days) AS percentile_rank_of_7_day_los
FROM cohort_los
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;