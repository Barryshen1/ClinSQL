WITH AdmissionsFiltered AS (
            SELECT
                p.subject_id,
                a.hadm_id,
                a.admittime,
                a.dischtime,
                DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los_days,
                p.gender,
                p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
            FROM
                `physionet-data.mimiciv_3_1_hosp.patients` p
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.admissions` a
                ON p.subject_id = a.subject_id
            WHERE
                p.gender = 'M'
                AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 80 AND 90
        ),
        AcsAdmissions AS (
            SELECT DISTINCT
                af.subject_id,
                af.hadm_id,
                af.hospital_los_days
            FROM
                AdmissionsFiltered af
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                ON af.subject_id = di.subject_id
                AND af.hadm_id = di.hadm_id
            WHERE
                -- ICD-10 codes for ACS: Unstable Angina (I20.0), Acute Myocardial Infarction (I21.x, I22.x)
                (di.icd_version = 10 AND (LEFT(di.icd_code, 4) = 'I200' OR LEFT(di.icd_code, 3) = 'I21' OR LEFT(di.icd_code, 3) = 'I22'))
                OR
                -- ICD-9 codes for ACS: Myocardial Infarction (410.x), Other acute and subacute forms of ischemic heart disease (411.x - specifically 411.0, 411.1, 411.8 for unstable angina/intermediate syndrome)
                (di.icd_version = 9 AND (LEFT(di.icd_code, 3) = '410' OR LEFT(di.icd_code, 4) IN ('4110', '4111', '4118')))
        ),
        FirstHsTnT AS (
            SELECT
                le.subject_id,
                le.hadm_id,
                le.charttime,
                le.valuenum,
                le.valueuom,
                ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
            FROM
                AcsAdmissions aa
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.labevents` le
                ON aa.subject_id = le.subject_id
                AND aa.hadm_id = le.hadm_id
            WHERE
                le.itemid = 51000 -- Itemid for Troponin T, interpreted as hs-TnT in MIMIC-IV v3.1 context
                AND le.valuenum IS NOT NULL
                AND le.valuenum >= 0 -- Ensure non-negative value
                AND le.valueuom = 'ug/L' -- Ensure unit is micrograms per liter, as per common hs-TnT in MIMIC
        ),
        CategorizedHsTnT AS (
            SELECT
                fht.subject_id,
                fht.hadm_id,
                aa.hospital_los_days,
                fht.valuenum AS hs_tnt_value,
                CASE
                    WHEN fht.valuenum < 0.006 THEN 'Normal' -- < 6 ng/L equivalent
                    WHEN fht.valuenum >= 0.006 AND fht.valuenum < 0.1 THEN 'Borderline' -- 6 - 99 ng/L equivalent
                    WHEN fht.valuenum >= 0.1 THEN 'Myocardial Injury' -- >= 100 ng/L equivalent
                    ELSE 'Unknown'
                END AS tnt_category
            FROM
                FirstHsTnT fht
            INNER JOIN
                AcsAdmissions aa
                ON fht.subject_id = aa.subject_id AND fht.hadm_id = aa.hadm_id
            WHERE
                fht.rn = 1
        )
SELECT
    tnt_category,
    COUNT(DISTINCT hadm_id) AS number_of_admissions,
    ROUND(CAST(COUNT(DISTINCT hadm_id) AS NUMERIC) * 100.0 / SUM(COUNT(DISTINCT hadm_id)) OVER (), 2) AS percentage_of_admissions,
    ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days
FROM
    CategorizedHsTnT
WHERE
    tnt_category != 'Unknown' -- Exclude any 'Unknown' categories if they somehow appear (should be rare/none)
GROUP BY
    tnt_category
ORDER BY
    CASE tnt_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Myocardial Injury' THEN 3
        ELSE 4
    END;